//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"evik/backend/internal/infrastructure/postgres"
)

// seedCompletedOrder inserts a financially-closed completed order for driverID
// with a valid split (driver_amount + commission_amount == price_total) and the
// given payment method and financial-completion timestamp.
func seedCompletedOrder(t *testing.T, db *sql.DB, userID, driverID, method string, completedAt time.Time, driverAmount, commission int64) {
	t.Helper()
	orderID := "order-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
	tow_truck_type, status, price_total, driver_amount, commission_amount, payment_method,
	financially_completed_at, financial_status, created_at, updated_at)
VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', $4, $5, $6, $7, $8, 'completed', NOW(), NOW())`,
		orderID, userID, driverID, driverAmount+commission, driverAmount, commission, method, completedAt); err != nil {
		t.Fatalf("insert completed order: %v", err)
	}
}

// TestGetDriverEarnings verifies the /driver/earnings aggregate: 3 card orders
// completed today and 2 cash orders completed earlier in the same week yield
// today.orders = 3 and week.orders = 5, and a cash order contributes to earnings
// identically to a card order (both count driver_amount).
func TestGetDriverEarnings(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	userID := "user-" + uuid()
	seedUser(t, db, userID, "client")

	driverUserID := "driver-" + uuid()
	seedUser(t, db, driverUserID, "driver")
	seedDriver(t, db, driverUserID)
	driverID := driverUserID

	// Period boundaries mirror the handler (Europe/Moscow).
	loc, err := time.LoadLocation("Europe/Moscow")
	if err != nil {
		loc = time.UTC
	}
	now := time.Now().In(loc)
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7
	}
	weekStart := todayStart.AddDate(0, 0, -(weekday - 1))

	const driverAmount = int64(425000)
	const commission = int64(75000)

	// 3 card orders completed today.
	todayAt := todayStart.Add(12 * time.Hour)
	for i := 0; i < 3; i++ {
		seedCompletedOrder(t, db, userID, driverID, "card", todayAt, driverAmount, commission)
	}
	// 2 cash orders completed earlier in the current week (Monday noon).
	earlierAt := weekStart.Add(12 * time.Hour)
	for i := 0; i < 2; i++ {
		seedCompletedOrder(t, db, userID, driverID, "cash", earlierAt, driverAmount, commission)
	}

	payRepo := postgres.NewPaymentRepository(db)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	e, err := payRepo.GetDriverEarnings(context.Background(), driverID, todayStart, weekStart, monthStart)
	if err != nil {
		t.Fatalf("GetDriverEarnings: %v", err)
	}

	// week always includes all 5 orders (both timestamps >= weekStart).
	if e.WeekOrders != 5 {
		t.Errorf("week.orders: expected 5, got %d", e.WeekOrders)
	}
	if e.WeekAmount != 5*driverAmount {
		t.Errorf("week.amount: expected %d, got %d", 5*driverAmount, e.WeekAmount)
	}

	// today includes only the 3 card orders — unless today is Monday, in which
	// case weekStart == todayStart and the 2 cash orders also fall in "today".
	expectedTodayOrders := int64(3)
	if todayStart.Equal(weekStart) {
		expectedTodayOrders = 5
	}
	if e.TodayOrders != expectedTodayOrders {
		t.Errorf("today.orders: expected %d, got %d", expectedTodayOrders, e.TodayOrders)
	}
	if e.TodayAmount != expectedTodayOrders*driverAmount {
		t.Errorf("today.amount: expected %d, got %d", expectedTodayOrders*driverAmount, e.TodayAmount)
	}

	// A cash order contributes the same driver_amount as a card order: the week
	// total is exactly 5 * driverAmount regardless of payment method.
	if e.WeekAmount != 5*driverAmount {
		t.Errorf("cash and card must contribute equally: expected %d, got %d", 5*driverAmount, e.WeekAmount)
	}
}
