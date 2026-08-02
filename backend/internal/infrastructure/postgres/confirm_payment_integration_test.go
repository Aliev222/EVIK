//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	"evik/backend/internal/infrastructure/postgres"
	paymentuc "evik/backend/internal/usecase/payment"
)

// TestConfirmPaymentCash_FreesDriverAndCompletesOrder verifies the /confirm-payment
// cash path is fully transactional: financial settlement, the completed-status
// write and the driver release all commit together. After a successful confirm
// the order is completed and financially closed, the driver is back online with
// current_order_id NULL, and the wallet carries the cash commission debt.
func TestConfirmPaymentCash_FreesDriverAndCompletesOrder(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-cp", "client")
	seedUser(t, db, "driver-cp", "driver")
	seedDriver(t, db, "driver-cp")

	_, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'cash', $4, $4)`,
		"order-cp", "client-cp", "driver-cp", now)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	// driver busy on this order — must be freed by the completion tx
	_, err = db.ExecContext(ctx, `UPDATE drivers SET status = 'busy', current_order_id = $1 WHERE id = $2`, "order-cp", "driver-cp")
	if err != nil {
		t.Fatalf("mark driver busy: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', $3, $3)`,
		"wallet_driver-cp", "driver-cp", now)
	if err != nil {
		t.Fatalf("insert driver wallet: %v", err)
	}

	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-cp": {
				ID:            "order-cp",
				UserID:        "client-cp",
				DriverID:      strPtr("driver-cp"),
				Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType:  orderdomain.TowTruckWinch,
				Status:        orderdomain.StatusAwaitingPayment,
				PriceTotal:    500000,
				PaymentMethod: "cash",
				CreatedAt:     now,
				UpdatedAt:     now,
			},
		},
	}
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(
		paymentRepo,
		orderRepo,
		releaseStore{},
		webhookPricingService{},
		&webhookProvider{},
		&webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}},
		webhookClock{now: now},
		webhookIDGen{},
		600,
		10000,
		nil,
	)

	payment, err := financeUC.ConfirmOrderPayment(ctx, "client-cp", "order-cp")
	if err != nil {
		t.Fatalf("ConfirmOrderPayment failed: %v", err)
	}
	if payment != nil {
		t.Fatalf("cash confirm payment = %v, want nil", payment)
	}

	// order: completed + financially closed
	var status, finStatus string
	err = db.QueryRowContext(ctx, `SELECT status, financial_status FROM orders WHERE id = $1`, "order-cp").Scan(&status, &finStatus)
	if err != nil {
		t.Fatalf("query order: %v", err)
	}
	if status != string(orderdomain.StatusCompleted) {
		t.Errorf("order status = %q, want %q", status, orderdomain.StatusCompleted)
	}
	if finStatus != "completed" {
		t.Errorf("order financial_status = %q, want 'completed'", finStatus)
	}

	// driver: released — current_order_id NULL and back online
	var cur sql.NullString
	var dstatus string
	err = db.QueryRowContext(ctx, `SELECT current_order_id, status FROM drivers WHERE id = $1`, "driver-cp").Scan(&cur, &dstatus)
	if err != nil {
		t.Fatalf("query driver: %v", err)
	}
	if cur.Valid {
		t.Errorf("driver current_order_id = %q, want NULL (driver must be freed)", cur.String)
	}
	if dstatus != "online" {
		t.Errorf("driver status = %q, want 'online'", dstatus)
	}

	// wallet: cash commission debt = 15% of 500000 = 75000 kopecks
	var debt int64
	err = db.QueryRowContext(ctx, `SELECT debt_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-cp").Scan(&debt)
	if err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if debt != 75000 {
		t.Errorf("wallet debt_balance = %d, want 75000 (15%% of 500000)", debt)
	}
}

// TestConfirmPaymentCash_RollbackOnSettlementFailure verifies the all-or-nothing
// property at the DB level: when financial settlement fails inside the
// completion tx (order has no driver), the order status write is discarded and
// the order remains in awaiting_payment.
func TestConfirmPaymentCash_RollbackOnSettlementFailure(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-cr", "client")

	_, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'cash', $3, $3)`,
		"order-cr", "client-cr", now)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-cr": {
				ID:            "order-cr",
				UserID:        "client-cr",
				Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType:  orderdomain.TowTruckWinch,
				Status:        orderdomain.StatusAwaitingPayment,
				PriceTotal:    500000,
				PaymentMethod: "cash",
				CreatedAt:     now,
				UpdatedAt:     now,
			},
		},
	}
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(
		paymentRepo,
		orderRepo,
		releaseStore{},
		webhookPricingService{},
		&webhookProvider{},
		&webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}},
		webhookClock{now: now},
		webhookIDGen{},
		600,
		10000,
		nil,
	)

	_, err = financeUC.ConfirmOrderPayment(ctx, "client-cr", "order-cr")
	if err == nil {
		t.Fatal("expected error when settlement fails (order has no driver), got nil")
	}

	var status string
	err = db.QueryRowContext(ctx, `SELECT status FROM orders WHERE id = $1`, "order-cr").Scan(&status)
	if err != nil {
		t.Fatalf("query order: %v", err)
	}
	if status != string(orderdomain.StatusAwaitingPayment) {
		t.Errorf("order status = %q, want %q (status write must be rolled back with the failed settlement)", status, orderdomain.StatusAwaitingPayment)
	}
}
