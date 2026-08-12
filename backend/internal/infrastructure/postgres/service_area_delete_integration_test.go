//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	servicearea "evik/backend/internal/domain/servicearea"
	"evik/backend/internal/infrastructure/postgres"
)

// Delete of a service area must respect both existing safeguards:
//   - active (non-terminal) orders inside its bounds  -> ErrAreaHasActiveOrders
//   - any row still referencing the area via FK (e.g. orders.city_id, even
//     historical/completed ones)                     -> ErrAreaInUse
// and succeed when the area is genuinely unused.

func insertArea(t testing.TB, db *sql.DB, id string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, center_lat, center_lng, radius_km, is_active, created_at, updated_at)
VALUES ($1, $2, $3, 40.0, 45.0, 44.0, 50.0, 42.0, 47.5, 25, TRUE, NOW(), NOW())`,
		id, "Test area "+id, "test-area-"+id); err != nil {
		t.Fatalf("insert service area %s: %v", id, err)
	}
}

func TestServiceAreaDelete_UnusedAreaSucceeds(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewServiceAreaRepository(db)

	id := "area-free-" + uuid()
	insertArea(t, db, id)
	defer db.Exec(`DELETE FROM service_areas WHERE id = $1`, id)

	if err := repo.Delete(ctx, id); err != nil {
		t.Fatalf("delete unused area: %v", err)
	}
	// Row must actually be gone.
	if _, err := repo.GetByID(ctx, id); !errors.Is(err, servicearea.ErrNotFound) {
		t.Fatalf("GetByID after delete = %v, want ErrNotFound", err)
	}
}

func TestServiceAreaDelete_InUseByOrderIsErrAreaInUse(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewServiceAreaRepository(db)

	seedUser(t, db, "client-zone-inuse", "client")
	areaID := "area-inuse-" + uuid()
	insertArea(t, db, areaID)
	defer db.Exec(`DELETE FROM service_areas WHERE id = $1`, areaID)

	// A historical (completed) order still references the area via city_id.
	// The active-orders geo check passes (order is terminal), so the FK
	// constraint is the only thing standing in the way -> ErrAreaInUse.
	orderID := "order-zone-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, commission_amount, driver_amount, city_id, financially_completed_at, financial_status, created_at, updated_at)
VALUES ($1, 'client-zone-inuse', 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', 500000, 150000, 350000, $2, NOW(), 'completed', NOW(), NOW())`,
		orderID, areaID); err != nil {
		t.Fatalf("insert referencing order: %v", err)
	}
	defer db.Exec(`DELETE FROM orders WHERE id = $1`, orderID)

	if err := repo.Delete(ctx, areaID); !errors.Is(err, servicearea.ErrAreaInUse) {
		t.Fatalf("err = %v, want ErrAreaInUse", err)
	}
	// The area must still exist.
	if _, err := repo.GetByID(ctx, areaID); err != nil {
		t.Fatalf("area should still exist after failed delete: %v", err)
	}
}

func TestServiceAreaDelete_HasActiveOrdersIsErrAreaHasActiveOrders(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewServiceAreaRepository(db)

	seedUser(t, db, "client-zone-active", "client")
	areaID := "area-active-" + uuid()
	insertArea(t, db, areaID)
	defer db.Exec(`DELETE FROM service_areas WHERE id = $1`, areaID)

	// Active (searching) order inside the bounds, WITHOUT city_id reference.
	orderID := "order-active-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, created_at, updated_at)
VALUES ($1, 'client-zone-active', 42.0, 47.5, 42.1, 47.6, 'winch', 'searching', 500000, NOW(), NOW())`,
		orderID); err != nil {
		t.Fatalf("insert active order: %v", err)
	}
	defer db.Exec(`DELETE FROM orders WHERE id = $1`, orderID)

	if err := repo.Delete(ctx, areaID); !errors.Is(err, servicearea.ErrAreaHasActiveOrders) {
		t.Fatalf("err = %v, want ErrAreaHasActiveOrders", err)
	}
}

func TestServiceAreaDelete_HistoricalOrderWithoutCityIsOK(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewServiceAreaRepository(db)

	seedUser(t, db, "client-zone-hist", "client")
	areaID := "area-hist-" + uuid()
	insertArea(t, db, areaID)
	defer db.Exec(`DELETE FROM service_areas WHERE id = $1`, areaID)

	// A completed order inside the bounds but with no city_id reference: it is
	// neither "active" nor holds an FK, so deletion must succeed.
	orderID := "order-hist-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, commission_amount, driver_amount, financially_completed_at, financial_status, created_at, updated_at)
VALUES ($1, 'client-zone-hist', 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', 500000, 150000, 350000, NOW(), 'completed', NOW(), NOW())`,
		orderID); err != nil {
		t.Fatalf("insert historical order: %v", err)
	}
	defer db.Exec(`DELETE FROM orders WHERE id = $1`, orderID)

	if err := repo.Delete(ctx, areaID); err != nil {
		t.Fatalf("delete area with only historical non-referencing order: %v", err)
	}
}
