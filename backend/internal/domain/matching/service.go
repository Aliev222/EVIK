package matching

import (
	"context"
	"errors"
	"sync"
	"time"

	"evik/backend/internal/domain/driver"
	"evik/backend/internal/domain/location"
	"evik/backend/internal/domain/order"
)

var ErrNoCandidateDrivers = errors.New("no candidate drivers")

type NearbyDriverRepository interface {
	GetNearbyDrivers(ctx context.Context, pickup location.Location, radiusKM float64, limit int) ([]location.DriverLocation, error)
}

type MatchingService interface {
	FindNearestDriver(ctx context.Context, order *order.Order) (*driver.Driver, error)
}

type nearestMatchingService struct {
	mu         sync.Mutex
	repo       NearbyDriverRepository
	maxRadius  float64
	stepRadius float64
	stepDelay  time.Duration
	limit      int
}

func NewNearestMatchingService(repo NearbyDriverRepository) MatchingService {
	return &nearestMatchingService{
		repo:       repo,
		maxRadius:  15,
		stepRadius: 2,
		stepDelay:  3 * time.Second,
		limit:      5,
	}
}

func (s *nearestMatchingService) FindNearestDriver(ctx context.Context, ord *order.Order) (*driver.Driver, error) {
	s.mu.Lock()
	maxRadius := s.maxRadius
	stepRadius := s.stepRadius
	stepDelay := s.stepDelay
	limit := s.limit
	s.mu.Unlock()

	pickup := location.Location{
		Lat:       ord.Pickup.Lat,
		Lng:       ord.Pickup.Lng,
		UpdatedAt: time.Now().UTC(),
	}

	for radius := stepRadius; radius <= maxRadius; radius += stepRadius {
		drivers, err := s.repo.GetNearbyDrivers(ctx, pickup, radius, limit)
		if err != nil {
			return nil, err
		}
		if len(drivers) > 0 {
			best := drivers[0]
			for i := 1; i < len(drivers); i++ {
				if drivers[i].DistanceKM < best.DistanceKM {
					best = drivers[i]
				}
			}
			return &driver.Driver{ID: best.DriverID, IsReady: true}, nil
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(stepDelay):
		}
	}
	return nil, ErrNoCandidateDrivers
}

// ExpandSearchRadius allows orchestration layer to increase search window between retries.
func (s *nearestMatchingService) ExpandSearchRadius() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.maxRadius += s.stepRadius
}
