//go:build integration

package postgres_test

import (
	"context"
	"testing"

	"evik/backend/internal/infrastructure/postgres"
)

// TestListDriverOrders_CompletedColumn регресс на БАГ №1: ListDriverOrders
// должен использовать существующую колонку financially_completed_at, а не
// несуществующую o.completed_at (краш GET /admin/drivers/{id}/orders).
func TestListDriverOrders_CompletedColumn(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()

	seedUser(t, db, "client-1", "client")
	seedUser(t, db, "driver-1", "driver")
	seedDriver(t, db, "driver-1")

	// Завершённый заказ — financially_completed_at установлен, драйвер назначен.
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, driver_amount, commission_amount, financially_completed_at, financial_status, created_at, updated_at)
VALUES ('order-completed', 'client-1', 'driver-1', 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', 500000, 500000, 0, NOW(), 'completed', NOW(), NOW())`); err != nil {
		t.Fatalf("insert completed order: %v", err)
	}

	// Незавершённый заказ — financially_completed_at IS NULL (проверка NULL-скана в *time.Time).
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, driver_amount, commission_amount, financial_status, created_at, updated_at)
VALUES ('order-created', 'client-1', 'driver-1', 42.2, 47.5, 42.3, 47.6, 'winch', 'created', 300000, 0, 0, 'pending', NOW(), NOW())`); err != nil {
		t.Fatalf("insert created order: %v", err)
	}

	// Заказ другого драйвера — не должен попасть в выборку.
	seedUser(t, db, "driver-2", "driver")
	seedDriver(t, db, "driver-2")
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, driver_amount, commission_amount, financial_status, created_at, updated_at)
VALUES ('order-other', 'client-1', 'driver-2', 42.4, 47.5, 42.5, 47.6, 'winch', 'created', 100000, 0, 0, 'pending', NOW(), NOW())`); err != nil {
		t.Fatalf("insert other driver order: %v", err)
	}

	repo := postgres.NewAdminRepository(db)
	items, total, err := repo.ListDriverOrders(ctx, "driver-1", 50, 0)
	if err != nil {
		t.Fatalf("ListDriverOrders failed: %v", err)
	}

	if total != 2 {
		t.Fatalf("expected total 2 orders for driver-1, got %d", total)
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}

	byID := make(map[string]int)
	for i, it := range items {
		byID[it.OrderID] = i
	}

	idx, ok := byID["order-completed"]
	if !ok {
		t.Fatalf("completed order missing from results: %v", byID)
	}
	if items[idx].CompletedAt == nil {
		t.Fatalf("expected non-nil CompletedAt for completed order, got nil")
	}

	idx, ok = byID["order-created"]
	if !ok {
		t.Fatalf("created order missing from results: %v", byID)
	}
	if items[idx].CompletedAt != nil {
		t.Fatalf("expected nil CompletedAt for not-completed order, got %v", *items[idx].CompletedAt)
	}

	if _, ok := byID["order-other"]; ok {
		t.Fatalf("order of another driver leaked into results")
	}
}
