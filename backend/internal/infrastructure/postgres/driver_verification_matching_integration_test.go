//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"evik/backend/internal/domain/location"
	matchingdomain "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/postgres"
)

// seedDriverWithVerification inserts a driver (user_id = driver id by default)
// and its single driver_verifications row with the given status.
func seedDriverWithVerification(t *testing.T, db *sql.DB, driverID, status string, currentOrderID *string) {
	t.Helper()
	seedUser(t, db, driverID, "driver")
	if _, err := db.Exec(`
INSERT INTO drivers (id, user_id, status, current_order_id, last_seen_at, updated_at)
VALUES ($1, $2, 'online', $3, NOW(), NOW())`, driverID, driverID, currentOrderID); err != nil {
		t.Fatalf("insert driver %s: %v", driverID, err)
	}
	if _, err := db.Exec(`
INSERT INTO driver_verifications (id, user_id, full_name, phone, city, vehicle_model, vehicle_plate, vehicle_type, status, submitted_at, updated_at)
VALUES ($1, $2, 'Driver', '79990000000', 'Moscow', 'GAZ', 'A000AA77', 'winch', $3, NOW(), NOW())`,
		driverID, driverID, status); err != nil {
		t.Fatalf("insert verification for %s: %v", driverID, err)
	}
}

// setDriverBusy points the driver at a live order (status busy + current_order_id)
// and marks the order as owned by the driver, mirroring an accepted order.
func setDriverBusy(t *testing.T, db *sql.DB, driverID, orderID string) {
	t.Helper()
	if _, err := db.Exec(`UPDATE drivers SET status = 'busy', current_order_id = $2, updated_at = NOW() WHERE id = $1`, driverID, orderID); err != nil {
		t.Fatalf("set driver busy: %v", err)
	}
	if _, err := db.Exec(`UPDATE orders SET driver_id = $2, updated_at = NOW() WHERE id = $1`, orderID, driverID); err != nil {
		t.Fatalf("assign order to driver: %v", err)
	}
}

// TestDriverIsAvailable_RequiresApprovedVerification covers the critical-path
// filter: approved online driver without an order is the only candidate.
func TestDriverIsAvailable_RequiresApprovedVerification(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewDriverRepository(db, nil)

	t.Run("approved online without order is available", func(t *testing.T) {
		seedDriverWithVerification(t, db, "d-ok", "approved", nil)
		ok, err := repo.IsAvailable(ctx, "d-ok")
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if !ok {
			t.Fatal("approved online driver should be available")
		}
	})

	t.Run("blocked online without order is NOT available", func(t *testing.T) {
		seedDriverWithVerification(t, db, "d-blocked", "blocked", nil)
		ok, err := repo.IsAvailable(ctx, "d-blocked")
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("blocked online driver must NOT be available")
		}
	})

	t.Run("blocked with active order is NOT available and order untouched", func(t *testing.T) {
		clientID := "client-order"
		driverID := "d-blocked-order"
		orderID := "order-blocked"
		seedUser(t, db, clientID, "client")
		seedDriverWithVerification(t, db, driverID, "blocked", nil)
		seedOrderRaw(t, db, orderID, clientID)
		setOrderSearching(t, db, orderID)
		setDriverBusy(t, db, driverID, orderID)

		ok, err := repo.IsAvailable(ctx, driverID)
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("blocked driver with active order must NOT be available")
		}

		// "Deferred blocking": current order is left intact — no cancellation.
		var status string
		var orderStatus string
		var orderDriverID *string
		if err := db.QueryRow(`SELECT status FROM drivers WHERE id = $1`, driverID).Scan(&status); err != nil {
			t.Fatalf("query driver: %v", err)
		}
		if status != "busy" {
			t.Fatalf("driver status = %q, want 'busy' (order must not be interrupted)", status)
		}
		if err := db.QueryRow(`SELECT status, driver_id FROM orders WHERE id = $1`, orderID).Scan(&orderStatus, &orderDriverID); err != nil {
			t.Fatalf("query order: %v", err)
		}
		if orderStatus != string(orderdomain.StatusSearching) {
			t.Fatalf("order status = %q, want 'searching' (blocking must not cancel the order)", orderStatus)
		}
		if orderDriverID == nil || *orderDriverID != driverID {
			t.Fatalf("order driver_id = %v, want %s", orderDriverID, driverID)
		}
	})

	t.Run("pending is NOT available", func(t *testing.T) {
		seedDriverWithVerification(t, db, "d-pending", "pending", nil)
		ok, err := repo.IsAvailable(ctx, "d-pending")
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("pending driver must NOT be available")
		}
	})

	t.Run("rejected is NOT available", func(t *testing.T) {
		seedDriverWithVerification(t, db, "d-rejected", "rejected", nil)
		ok, err := repo.IsAvailable(ctx, "d-rejected")
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("rejected driver must NOT be available")
		}
	})

	t.Run("changes_requested is NOT available", func(t *testing.T) {
		seedDriverWithVerification(t, db, "d-changes", "changes_requested", nil)
		ok, err := repo.IsAvailable(ctx, "d-changes")
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("changes_requested driver must NOT be available")
		}
	})

	t.Run("approved with active order is NOT available", func(t *testing.T) {
		clientID := "client-busy"
		driverID := "d-ok-busy"
		orderID := "order-ok-busy"
		seedUser(t, db, clientID, "client")
		seedDriverWithVerification(t, db, driverID, "approved", nil)
		seedOrderRaw(t, db, orderID, clientID)
		setOrderSearching(t, db, orderID)
		setDriverBusy(t, db, driverID, orderID)

		ok, err := repo.IsAvailable(ctx, driverID)
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("approved but busy driver must NOT be available")
		}
	})

	t.Run("no verification row is NOT available", func(t *testing.T) {
		seedUser(t, db, "d-nover", "driver")
		seedDriver(t, db, "d-nover")
		ok, err := repo.IsAvailable(ctx, "d-nover")
		if err != nil {
			t.Fatalf("IsAvailable: %v", err)
		}
		if ok {
			t.Fatal("driver without verification must NOT be available")
		}
	})
}

// stubNearbyRepo is a deterministic geo source for FindCandidates integration:
// it returns the configured driver IDs as geometrically nearby. Availability
// is then resolved through the real postgres DriverRepository.IsAvailable.
type stubNearbyRepo struct {
	ids []string
}

func (s *stubNearbyRepo) GetNearbyDrivers(_ context.Context, _ location.Location, _ float64, _ int) ([]location.DriverLocation, error) {
	out := make([]location.DriverLocation, 0, len(s.ids))
	for i, id := range s.ids {
		out = append(out, location.DriverLocation{
			DriverID:   id,
			Location:   location.Location{Lat: 55.0, Lng: 37.0, UpdatedAt: time.Now().UTC()},
			DistanceKM: float64(i + 1),
		})
	}
	return out, nil
}

type allOnlineLiveChecker struct{}

func (allOnlineLiveChecker) HasDriver(string) bool { return true }

// TestFindCandidates_ExcludesNonApprovedDrivers runs the real matching chain
// (FindCandidates → postgres DriverRepository.IsAvailable) and asserts the
// candidate pool only contains approved, free drivers.
func TestFindCandidates_ExcludesNonApprovedDrivers(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()

	seedDriverWithVerification(t, db, "can-approved", "approved", nil)
	seedDriverWithVerification(t, db, "can-blocked", "blocked", nil)
	seedDriverWithVerification(t, db, "can-pending", "pending", nil)
	seedDriverWithVerification(t, db, "can-rejected", "rejected", nil)

	clientID := "client-cc"
	orderID := "order-cc"
	seedUser(t, db, clientID, "client")
	seedDriverWithVerification(t, db, "can-blocked-order", "blocked", nil)
	seedOrderRaw(t, db, orderID, clientID)
	setOrderSearching(t, db, orderID)
	setDriverBusy(t, db, "can-blocked-order", orderID)

	svc := matchingdomain.NewNearestMatchingService(
		&stubNearbyRepo{ids: []string{"can-approved", "can-blocked", "can-pending", "can-rejected", "can-blocked-order"}},
		postgres.NewDriverRepository(db, nil),
	)

	candidates, err := svc.FindCandidates(ctx, &orderdomain.Order{
		Pickup: orderdomain.Coordinate{Lat: 55.0, Lng: 37.0},
	}, 10, nil, allOnlineLiveChecker{}, time.Minute)
	if err != nil {
		t.Fatalf("FindCandidates: %v", err)
	}

	if len(candidates) != 1 {
		t.Fatalf("expected exactly 1 candidate (approved only), got %d: %+v", len(candidates), candidates)
	}
	if candidates[0].DriverID != "can-approved" {
		t.Fatalf("candidate = %s, want can-approved", candidates[0].DriverID)
	}

	// The active order of the blocked driver is untouched.
	var orderStatus string
	var orderDriverID *string
	if err := db.QueryRow(`SELECT status, driver_id FROM orders WHERE id = $1`, orderID).Scan(&orderStatus, &orderDriverID); err != nil {
		t.Fatalf("query order: %v", err)
	}
	if orderStatus != string(orderdomain.StatusSearching) {
		t.Fatalf("order status = %q, want 'searching'", orderStatus)
	}
	if orderDriverID == nil || *orderDriverID != "can-blocked-order" {
		t.Fatalf("order driver_id = %v, want can-blocked-order", orderDriverID)
	}
}

// TestFindCandidates_OnlyBlockedDrivers_NoCandidates asserts the dispatcher's
// no-candidate sentinel is returned when every nearby driver is blocked.
func TestFindCandidates_OnlyBlockedDrivers_NoCandidates(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()

	seedDriverWithVerification(t, db, "d-blocked-1", "blocked", nil)
	seedDriverWithVerification(t, db, "d-blocked-2", "blocked", nil)

	svc := matchingdomain.NewNearestMatchingService(
		&stubNearbyRepo{ids: []string{"d-blocked-1", "d-blocked-2"}},
		postgres.NewDriverRepository(db, nil),
	)

	_, err := svc.FindCandidates(ctx, &orderdomain.Order{
		Pickup: orderdomain.Coordinate{Lat: 55.0, Lng: 37.0},
	}, 10, nil, allOnlineLiveChecker{}, time.Minute)
	if err != matchingdomain.ErrNoCandidateDrivers {
		t.Fatalf("err = %v, want ErrNoCandidateDrivers", err)
	}
}
