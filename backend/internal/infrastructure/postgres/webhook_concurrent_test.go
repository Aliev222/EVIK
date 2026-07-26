//go:build integration

package postgres_test

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	"evik/backend/internal/infrastructure/postgres"
	paymentuc "evik/backend/internal/usecase/payment"
)

// TestWebhook_ConcurrentDuplicate verifies that two simultaneous webhook
// requests with the same eventID do not double-credit the driver wallet.
// Relies on CheckProcessed's INSERT ... ON CONFLICT serializing on the
// payment_webhooks unique index.
func TestWebhook_ConcurrentDuplicate(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-cc", "client")
	seedUser(t, db, "driver-cc", "driver")
	seedDriver(t, db, "driver-cc")

	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-cc": {
				ID: "order-cc", UserID: "client-cc", DriverID: strPtr("driver-cc"),
				Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Dropoff: orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType: orderdomain.TowTruckWinch, Status: orderdomain.StatusAccepted,
				PriceTotal: 500000, PaymentMethod: "card", CreatedAt: now, UpdatedAt: now,
			},
		},
	}
	provider := &webhookProvider{}
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, orderRepo, releaseStore{}, webhookPricingService{}, provider, &webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}}, webhookClock{now: now}, webhookIDGen{}, 600, 10000, nil)

	payload, err := json.Marshal(map[string]any{
		"event": "payment.succeeded",
		"object": map[string]any{
			"id":     "p-cc",
			"status": "succeeded",
			"paid":   true,
			"metadata": map[string]string{
				"purpose":  "order",
				"order_id": "order-cc",
			},
		},
	})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	verifier := paymentuc.NewYooKassaVerifier()

	for i := 0; i < 50; i++ {
		t.Run(fmt.Sprintf("iter-%d", i), func(t *testing.T) {
			if _, err := db.ExecContext(ctx, `DELETE FROM wallet_transactions`); err != nil {
				t.Fatalf("delete wallet_transactions: %v", err)
			}
			if _, err := db.ExecContext(ctx, `DELETE FROM payment_webhooks`); err != nil {
				t.Fatalf("delete payment_webhooks: %v", err)
			}
			if _, err := db.ExecContext(ctx, `DELETE FROM payments WHERE id = $1`, "payment-cc"); err != nil {
				t.Fatalf("delete payment: %v", err)
			}
			if _, err := db.ExecContext(ctx, `DELETE FROM orders WHERE id = $1`, "order-cc"); err != nil {
				t.Fatalf("delete order: %v", err)
			}
			if _, err := db.ExecContext(ctx, `
				INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
					tow_truck_type, status, price_total, payment_method, created_at, updated_at)
				VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'card', $4, $4)
				`, "order-cc", "client-cc", "driver-cc", now); err != nil {
				t.Fatalf("insert order: %v", err)
			}
			if _, err := db.ExecContext(ctx, `
				INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
					amount, currency, status, idempotency_key, created_at, updated_at)
				VALUES ($1, $2, $3, 'yookassa', 'p-cc', 'card', 'order', 500000, 'RUB', 'pending', 'ik-cc', $4, $4)
				`, "payment-cc", "order-cc", "client-cc", now); err != nil {
				t.Fatalf("insert payment: %v", err)
			}
			if _, err := db.ExecContext(ctx, `
				UPDATE driver_wallets SET pending_balance = 0, debt_balance = 0, available_balance = 0, updated_at = NOW() WHERE id = $1
				`, "wallet_driver-cc"); err != nil {
				t.Fatalf("reset wallet: %v", err)
			}

			orderRepo.orders["order-cc"].Status = orderdomain.StatusAwaitingPayment
			orderRepo.updateCalls = 0

			var wg sync.WaitGroup
			start := make(chan struct{})
			errs := make([]error, 2)

			for idx := 0; idx < 2; idx++ {
				wg.Add(1)
				go func(n int) {
					defer wg.Done()
					<-start
					errs[n] = financeUC.HandleProviderWebhook(ctx, verifier, payload)
				}(idx)
			}
			close(start)
			wg.Wait()

			for idx, e := range errs {
				if e != nil {
					t.Errorf("call %d returned error: %v", idx, e)
				}
			}

			var webhookCount int
			_ = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_webhooks WHERE id = $1`, "payment.succeeded:p-cc").Scan(&webhookCount)
			if webhookCount != 1 {
				t.Errorf("payment_webhooks rows = %d, want 1", webhookCount)
			}

			var processed bool
			_ = db.QueryRowContext(ctx, `SELECT processed FROM payment_webhooks WHERE id = $1`, "payment.succeeded:p-cc").Scan(&processed)
			if !processed {
				t.Error("payment_webhooks.processed = false, want true")
			}

			var incomeCount int
			_ = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE wallet_id = $1 AND type = 'order_income'`, "wallet_driver-cc").Scan(&incomeCount)
			if incomeCount != 1 {
				t.Errorf("order_income wallet_transactions = %d, want 1", incomeCount)
			}

			var pending int64
			_ = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-cc").Scan(&pending)
			if pending != 425000 {
				t.Errorf("pending_balance = %d, want 425000 (double-credit would be 850000)", pending)
			}
		})
	}
}
