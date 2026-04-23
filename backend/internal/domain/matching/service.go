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

type DriverAvailabilityRepository interface {
	IsAvailable(ctx context.Context, id string) (bool, error)
}

type MatchingService interface {
	FindNearestDriver(ctx context.Context, order *order.Order) (*driver.Driver, error)
}

type nearestMatchingService struct {
	mu               sync.Mutex
	repo             NearbyDriverRepository
	driverRepository DriverAvailabilityRepository
	maxRadius        float64
	stepRadius       float64
	stepDelay        time.Duration
	limit            int
}

func NewNearestMatchingService(repo NearbyDriverRepository, driverRepository DriverAvailabilityRepository) MatchingService {
	return &nearestMatchingService{
		repo:             repo,
		driverRepository: driverRepository,
		maxRadius:        15,
		stepRadius:       2,
		stepDelay:        3 * time.Second,
		limit:            5,
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
			for _, candidate := range drivers {
				available, err := s.driverRepository.IsAvailable(ctx, candidate.DriverID)
				if err != nil {
					return nil, err
				}
				if available {
					return &driver.Driver{
						ID:     candidate.DriverID,
						Status: driver.StatusOnline,
					}, nil
				}
			}
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
