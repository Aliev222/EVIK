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

// BatchAvailabilityChecker checks availability for multiple drivers in one query.
// Optional — when provided, FindCandidates uses batch check instead of N+1.
type BatchAvailabilityChecker interface {
	AreAvailable(ctx context.Context, ids []string) (map[string]bool, error)
}

type LiveDriverChecker interface {
	HasDriver(driverID string) bool
}

type Candidate struct {
	DriverID   string
	DistanceKM float64
	// NeedsWake is true when the driver is available in the DB (online, KYC
	// approved, no active order) but has no live WebSocket connection. The
	// dispatch scheduler must send a wake-up push and wait for the app to
	// reconnect before delivering the actual order offer.
	NeedsWake bool
}

type MatchingService interface {
	FindCandidates(ctx context.Context, ord *order.Order, radiusKM float64, exclude []string, liveChecker LiveDriverChecker, geoFreshness time.Duration) ([]Candidate, error)
}

type nearestMatchingService struct {
	mu               sync.Mutex
	repo             NearbyDriverRepository
	driverRepository DriverAvailabilityRepository
	batchChecker     BatchAvailabilityChecker
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
		limit:            20,
	}
}

func NewNearestMatchingServiceWithBatch(repo NearbyDriverRepository, driverRepository DriverAvailabilityRepository, batchChecker BatchAvailabilityChecker) MatchingService {
	return &nearestMatchingService{
		repo:             repo,
		driverRepository: driverRepository,
		batchChecker:     batchChecker,
		maxRadius:        15,
		stepRadius:       2,
		stepDelay:        3 * time.Second,
		limit:            20,
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

	// Filter: exclude list + geo freshness. The live-WS check is intentionally
	// NOT a hard filter: a driver who is online in the DB but has no live WS
	// (app backgrounded/killed) is still a valid candidate — the dispatcher
	// wakes them via push (see Candidate.NeedsWake). Only DB-online drivers
	// survive IsAvailable below, so we never offer to an offline driver.
	cutoff := time.Now().UTC().Add(-geoFreshness)
	var candidates []location.DriverLocation
	for _, d := range drivers {
		if _, excluded := excludeSet[d.DriverID]; excluded {
			continue
		}
		if d.Location.UpdatedAt.Before(cutoff) {
			continue
		}
		candidates = append(candidates, d)
	}

	if len(candidates) == 0 {
		return nil, ErrNoCandidateDrivers
	}

	// Batch availability check: single query instead of N+1
	availableIDs := make([]string, 0, len(candidates))
	if s.batchChecker != nil {
		ids := make([]string, len(candidates))
		for i, d := range candidates {
			ids[i] = d.DriverID
		}
		availMap, err := s.batchChecker.AreAvailable(ctx, ids)
		if err != nil {
			// Fallback to individual checks on batch failure
			for _, d := range candidates {
				ok, err := s.driverRepository.IsAvailable(ctx, d.DriverID)
				if err != nil {
					return nil, err
				}
				if ok {
					availableIDs = append(availableIDs, d.DriverID)
				}
			}
		} else {
			for _, d := range candidates {
				if availMap[d.DriverID] {
					availableIDs = append(availableIDs, d.DriverID)
				}
			}
		}
	} else {
		// No batch checker: individual N+1 checks (legacy path)
		for _, d := range candidates {
			available, err := s.driverRepository.IsAvailable(ctx, d.DriverID)
			if err != nil {
				return nil, err
			}
			if available {
				availableIDs = append(availableIDs, d.DriverID)
			}
		}
	}

	// Build result preserving distance order. A candidate is marked NeedsWake
	// when it is DB-available but has no live WebSocket (app not connected).
	liveSet := make(map[string]bool, len(candidates))
	if liveChecker != nil {
		for _, d := range candidates {
			liveSet[d.DriverID] = liveChecker.HasDriver(d.DriverID)
		}
	} else {
		// No live checker → treat every candidate as already connected.
		for _, d := range candidates {
			liveSet[d.DriverID] = true
		}
	}

	out := make([]Candidate, 0, len(availableIDs))
	availSet := make(map[string]struct{}, len(availableIDs))
	for _, id := range availableIDs {
		availSet[id] = struct{}{}
	}
	for _, d := range candidates {
		if _, ok := availSet[d.DriverID]; ok {
			out = append(out, Candidate{
				DriverID:   d.DriverID,
				DistanceKM: d.DistanceKM,
				NeedsWake:  !liveSet[d.DriverID],
			})
		}
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
