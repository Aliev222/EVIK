//go:build integration

package postgres_test

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	"evik/backend/internal/infrastructure/postgres"
	paymentuc "evik/backend/internal/usecase/payment"
)

// TestWebhook_ManyConcurrentDuplicates hardens the dedup guarantee from
// TestWebhook_ConcurrentDuplicate (2 goroutines) with 6 simultaneous duplicate
// deliveries of the same event: exactly one financial settlement may happen.
func TestWebhook_ManyConcurrentDuplicates(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-many", "client")
	seedUser(t, db, "driver-many", "driver")
	seedDriver(t, db, "driver-many")

	if _, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'card', $4, $4)`,
		"order-many", "client-many", "driver-many", now); err != nil {
		t.Fatalf("insert order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `
		INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
			amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'p-many', 'card', 'order', 500000, 'RUB', 'pending', 'ik-many', $4, $4)`,
		"payment-many", "order-many", "client-many", now); err != nil {
		t.Fatalf("insert payment: %v", err)
	}
	if _, err := db.ExecContext(ctx, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', $3, $3)`,
		"wallet_driver-many", "driver-many", now); err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-many": {
				ID: "order-many", UserID: "client-many", DriverID: strPtr("driver-many"),
				Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Dropoff: orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType: orderdomain.TowTruckWinch, Status: orderdomain.StatusAwaitingPayment,
				PriceTotal: 500000, PaymentMethod: "card", CreatedAt: now, UpdatedAt: now,
			},
		},
	}
	provider := &webhookProvider{}
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(
		paymentRepo, orderRepo, releaseStore{}, webhookPricingService{}, provider,
		&webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}},
		webhookClock{now: now}, webhookIDGen{}, 600, 10000, nil)

	payload, err := json.Marshal(map[string]any{
		"event": "payment.succeeded",
		"object": map[string]any{
			"id": "p-many", "status": "succeeded", "paid": true,
			"metadata": map[string]string{"purpose": "order", "order_id": "order-many"},
		},
	})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	verifier := paymentuc.NewYooKassaVerifier()

	const n = 6
	start := make(chan struct{})
	errs := make([]error, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			<-start
			errs[idx] = financeUC.HandleProviderWebhook(ctx, verifier, payload)
		}(i)
	}
	close(start)
	wg.Wait()

	for idx, e := range errs {
		if e != nil {
			t.Errorf("call %d returned error: %v", idx, e)
		}
	}

	var webhookCount int
	_ = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_webhooks WHERE id = $1`, "payment.succeeded:p-many").Scan(&webhookCount)
	if webhookCount != 1 {
		t.Errorf("payment_webhooks rows = %d, want 1", webhookCount)
	}

	var incomeCount int
	_ = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE wallet_id = $1 AND type = 'order_income'`, "wallet_driver-many").Scan(&incomeCount)
	if incomeCount != 1 {
		t.Errorf("order_income wallet_transactions = %d, want 1 (double-credit would be N)", incomeCount)
	}

	var pending int64
	_ = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-many").Scan(&pending)
	if pending != 425000 {
		t.Errorf("pending_balance = %d, want 425000", pending)
	}

	if provider.getPaymentCalls != 1 {
		t.Errorf("GetPayment calls = %d, want 1 (only the winning concurrent call reaches the provider)", provider.getPaymentCalls)
	}
}