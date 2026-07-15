package matching

import (
	"context"
	"testing"
	"time"

	"evik/backend/internal/domain/location"
	"evik/backend/internal/domain/order"
)

type fakeNearbyRepo struct {
	drivers []location.DriverLocation
	err     error
}

func (f *fakeNearbyRepo) GetNearbyDrivers(_ context.Context, _ location.Location, _ float64, _ int) ([]location.DriverLocation, error) {
	return f.drivers, f.err
}

type fakeAvailRepo struct {
	available map[string]bool
}

func (f *fakeAvailRepo) IsAvailable(_ context.Context, id string) (bool, error) {
	return f.available[id], nil
}

type fakeLiveChecker struct {
	online map[string]bool
}

func (f *fakeLiveChecker) HasDriver(driverID string) bool {
	return f.online[driverID]
}

func TestFindCandidates_ReturnsSortedByDistance(t *testing.T) {
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: []location.DriverLocation{
			{DriverID: "d2", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 2},
			{DriverID: "d1", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 5},
		},
	}, &fakeAvailRepo{available: map[string]bool{"d1": true, "d2": true}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	candidates, err := svc.FindCandidates(context.Background(), ord, 10, nil, &fakeLiveChecker{online: map[string]bool{"d1": true, "d2": true}}, time.Minute)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}
	if len(candidates) != 2 {
		t.Fatalf("got %d candidates, want 2", len(candidates))
	}
	if candidates[0].DriverID != "d2" || candidates[1].DriverID != "d1" {
		t.Fatalf("expected d2 first (2km), then d1 (5km), got %v", candidates)
	}
}

func TestFindCandidates_FiltersExclude(t *testing.T) {
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: []location.DriverLocation{
			{DriverID: "d1", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 1},
			{DriverID: "d2", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 2},
		},
	}, &fakeAvailRepo{available: map[string]bool{"d1": true, "d2": true}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	candidates, err := svc.FindCandidates(context.Background(), ord, 10, []string{"d1"}, &fakeLiveChecker{online: map[string]bool{"d1": true, "d2": true}}, time.Minute)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}
	if len(candidates) != 1 || candidates[0].DriverID != "d2" {
		t.Fatalf("expected only d2, got %v", candidates)
	}
}

func TestFindCandidates_FiltersStaleGeo(t *testing.T) {
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: []location.DriverLocation{
			{DriverID: "d1", Location: location.Location{UpdatedAt: time.Now().UTC().Add(-2 * time.Minute)}, DistanceKM: 1},
			{DriverID: "d2", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 2},
		},
	}, &fakeAvailRepo{available: map[string]bool{"d1": true, "d2": true}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	candidates, err := svc.FindCandidates(context.Background(), ord, 10, nil, &fakeLiveChecker{online: map[string]bool{"d1": true, "d2": true}}, 60*time.Second)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}
	if len(candidates) != 1 || candidates[0].DriverID != "d2" {
		t.Fatalf("expected only d2 (fresh geo), got %v", candidates)
	}
}

func TestFindCandidates_FiltersNoWS(t *testing.T) {
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: []location.DriverLocation{
			{DriverID: "d1", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 1},
			{DriverID: "d2", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 2},
		},
	}, &fakeAvailRepo{available: map[string]bool{"d1": true, "d2": true}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	candidates, err := svc.FindCandidates(context.Background(), ord, 10, nil, &fakeLiveChecker{online: map[string]bool{"d1": true}}, 60*time.Second)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}
	if len(candidates) != 1 || candidates[0].DriverID != "d1" {
		t.Fatalf("expected only d1 (has WS), got %v", candidates)
	}
}

func TestFindCandidates_FiltersUnavailable(t *testing.T) {
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: []location.DriverLocation{
			{DriverID: "d1", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 1},
			{DriverID: "d2", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 2},
		},
	}, &fakeAvailRepo{available: map[string]bool{"d1": false, "d2": true}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	candidates, err := svc.FindCandidates(context.Background(), ord, 10, nil, &fakeLiveChecker{online: map[string]bool{"d1": true, "d2": true}}, time.Minute)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}
	if len(candidates) != 1 || candidates[0].DriverID != "d2" {
		t.Fatalf("expected only d2 (available), got %v", candidates)
	}
}

func TestFindCandidates_NoPauses(t *testing.T) {
	start := time.Now()
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: []location.DriverLocation{
			{DriverID: "d1", Location: location.Location{UpdatedAt: time.Now().UTC()}, DistanceKM: 1},
		},
	}, &fakeAvailRepo{available: map[string]bool{"d1": true}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	_, err := svc.FindCandidates(context.Background(), ord, 10, nil, &fakeLiveChecker{online: map[string]bool{"d1": true}}, time.Minute)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}
	elapsed := time.Since(start)
	if elapsed > 100*time.Millisecond {
		t.Fatalf("FindCandidates took %v, expected <100ms (no pauses)", elapsed)
	}
}

func TestFindCandidates_ErrNoCandidates(t *testing.T) {
	svc := NewNearestMatchingService(&fakeNearbyRepo{
		drivers: nil,
	}, &fakeAvailRepo{available: map[string]bool{}})

	ord := &order.Order{Pickup: order.Coordinate{Lat: 55.75, Lng: 37.62}}
	_, err := svc.FindCandidates(context.Background(), ord, 10, nil, &fakeLiveChecker{}, time.Minute)
	if err != ErrNoCandidateDrivers {
		t.Fatalf("got %v, want ErrNoCandidateDrivers", err)
	}
}
