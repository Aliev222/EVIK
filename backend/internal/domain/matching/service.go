package matching

import (
	"context"
	"errors"
	"sync"
	"time"

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

type LiveDriverChecker interface {
	HasDriver(driverID string) bool
}

type Candidate struct {
	DriverID   string
	DistanceKM float64
}

type MatchingService interface {
	FindCandidates(ctx context.Context, ord *order.Order, radiusKM float64, exclude []string, liveChecker LiveDriverChecker, geoFreshness time.Duration) ([]Candidate, error)
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

// FindCandidates returns candidates sorted by distance ASC, without pauses.
// Filters: exclude list, geo freshness, IsAvailable, live WS connection.
func (s *nearestMatchingService) FindCandidates(ctx context.Context, ord *order.Order, radiusKM float64, exclude []string, liveChecker LiveDriverChecker, geoFreshness time.Duration) ([]Candidate, error) {
	excludeSet := make(map[string]struct{}, len(exclude))
	for _, id := range exclude {
		excludeSet[id] = struct{}{}
	}

	pickup := location.Location{
		Lat:       ord.Pickup.Lat,
		Lng:       ord.Pickup.Lng,
		UpdatedAt: time.Now().UTC(),
	}

	drivers, err := s.repo.GetNearbyDrivers(ctx, pickup, radiusKM, s.limit)
	if err != nil {
		return nil, err
	}

	cutoff := time.Now().UTC().Add(-geoFreshness)
	out := make([]Candidate, 0, len(drivers))
	for _, d := range drivers {
		if _, excluded := excludeSet[d.DriverID]; excluded {
			continue
		}
		if d.Location.UpdatedAt.Before(cutoff) {
			continue
		}
		if liveChecker != nil && !liveChecker.HasDriver(d.DriverID) {
			continue
		}
		available, err := s.driverRepository.IsAvailable(ctx, d.DriverID)
		if err != nil {
			return nil, err
		}
		if !available {
			continue
		}
		out = append(out, Candidate{
			DriverID:   d.DriverID,
			DistanceKM: d.DistanceKM,
		})
	}
	if len(out) == 0 {
		return nil, ErrNoCandidateDrivers
	}
	return out, nil
}

// ExpandSearchRadius allows orchestration layer to increase search window between retries.
func (s *nearestMatchingService) ExpandSearchRadius() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.maxRadius += s.stepRadius
}
