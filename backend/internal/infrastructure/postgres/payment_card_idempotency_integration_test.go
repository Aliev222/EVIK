//go:build integration

package postgres_test

import (
	"context"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
	"evik/backend/internal/infrastructure/postgres"
)

// B cover: the card-flow consistency mechanics at the database layer.
//   - AttachProviderPayment persists the provider stamp on a pre-inserted
//     pending row, so the local record always anchors provider money.
//   - Re-inserting the same idempotency_key (a retry after a partial failure)
//     returns the SAME row and never overwrites the already-attached provider
//     id -> no duplicate payment, no double charge.
//   - AttachPaymentMethodProvider stamps the payment_methods row so the
//     post-confirmation webhook can activate the bound card.

func TestPaymentCard_AttachProviderAndIdempotentRetry(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewPaymentRepository(db)

	seedUser(t, db, "client-card-1", "client")
	orderID := "order-card-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, created_at, updated_at)
VALUES ($1, 'client-card-1', 42.0, 47.5, 42.1, 47.6, 'winch', 'awaiting_payment', 800000, NOW(), NOW())`,
		orderID); err != nil {
		t.Fatalf("insert order: %v", err)
	}
	defer db.Exec(`DELETE FROM orders WHERE id = $1`, orderID)

	now := time.Date(2026, 8, 12, 12, 0, 0, 0, time.UTC)
	confURL := "https://yookassa.test/card/1"
	key := "order_payment:" + orderID + ":card"

	newPayment := func() *paymentdomain.Payment {
		return &paymentdomain.Payment{
			ID:             "pay-" + uuid(),
			OrderID:        &orderID,
			DriverID:       nil,
			UserID:         "client-card-1",
			Provider:       paymentdomain.ProviderYooKassa,
			PaymentMethod:  paymentdomain.PaymentMethodCard,
			Purpose:        paymentdomain.PaymentPurposeOrder,
			Amount:         800000,
			Currency:       paymentdomain.CurrencyRUB,
			Status:         paymentdomain.PaymentStatusPending,
			IdempotencyKey: key,
			CreatedAt:      now,
			UpdatedAt:      now,
		}
	}

	// Step 1: pre-insert the pending row (insert-first flow).
	created, err := repo.CreateOrderPayment(ctx, newPayment())
	if err != nil {
		t.Fatalf("CreateOrderPayment: %v", err)
	}
	// Step 2: attach the provider stamp.
	attached, err := repo.AttachProviderPayment(ctx, created.ID, "provider-card-1", "pending", &confURL, nil)
	if err != nil {
		t.Fatalf("AttachProviderPayment: %v", err)
	}
	if attached.ProviderPaymentID == nil || *attached.ProviderPaymentID != "provider-card-1" {
		t.Fatalf("attached provider id = %v, want provider-card-1", attached.ProviderPaymentID)
	}
	got, err := repo.GetPayment(ctx, created.ID)
	if err != nil {
		t.Fatalf("GetPayment: %v", err)
	}
	if got.ProviderPaymentID == nil || *got.ProviderPaymentID != "provider-card-1" {
		t.Fatalf("persisted provider id = %v, want provider-card-1", got.ProviderPaymentID)
	}
	if got.Status != paymentdomain.PaymentStatusPending || got.ConfirmationURL == nil || *got.ConfirmationURL != confURL {
		t.Fatalf("persisted payment = %+v, want status pending with confirmation url", got)
	}

	// Step 3: retry with the SAME idempotency key (e.g. after a transient
	// attach failure) and a DIFFERENT local payment id / provider id. The
	// ON CONFLICT must NOT create a second row and must preserve the first
	// provider id.
	retry := newPayment()
	retry.ID = "pay-retry-" + uuid()
	retry.ProviderPaymentID = nil
	retried, err := repo.CreateOrderPayment(ctx, retry)
	if err != nil {
		t.Fatalf("retry CreateOrderPayment: %v", err)
	}
	if retried.ID != created.ID {
		t.Fatalf("retry row id = %q, want original %q (must not duplicate)", retried.ID, created.ID)
	}
	// The returned row still carries the first provider stamp.
	if retried.ProviderPaymentID == nil || *retried.ProviderPaymentID != "provider-card-1" {
		t.Fatalf("retry provider id = %v, want surviving provider-card-1", retried.ProviderPaymentID)
	}
	// Exactly one row for this idempotency key.
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM payments WHERE idempotency_key = $1`, key).Scan(&count); err != nil {
		t.Fatalf("count payments: %v", err)
	}
	if count != 1 {
		t.Fatalf("payments for key = %d, want 1 (idempotent insert)", count)
	}
}

func TestPaymentCard_AttachPaymentMethodProvider(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewPaymentRepository(db)

	seedUser(t, db, "client-card-2", "client")
	methodID := "method-" + uuid()
	if _, err := db.Exec(`
INSERT INTO payment_methods (id, user_id, provider, provider_payment_method_id, provider_payment_id, brand, last4, exp_month, exp_year, holder, status, is_default, created_at)
VALUES ($1, 'client-card-2', 'yookassa', NULL, NULL, 'unknown', '0000', 0, 0, '', 'pending', FALSE, NOW())`,
		methodID); err != nil {
		t.Fatalf("insert pending method: %v", err)
	}
	defer db.Exec(`DELETE FROM payment_methods WHERE id = $1`, methodID)

	if err := repo.AttachPaymentMethodProvider(ctx, methodID, "provider-bind-1"); err != nil {
		t.Fatalf("AttachPaymentMethodProvider: %v", err)
	}
	var stored string
	if err := db.QueryRow(`SELECT COALESCE(provider_payment_id, '') FROM payment_methods WHERE id = $1`, methodID).Scan(&stored); err != nil {
		t.Fatalf("read method: %v", err)
	}
	if stored != "provider-bind-1" {
		t.Fatalf("method provider_payment_id = %q, want provider-bind-1", stored)
	}
}

func TestPaymentCard_AttachProviderPayment_UnknownID(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	repo := postgres.NewPaymentRepository(db)

	if _, err := repo.AttachProviderPayment(ctx, "does-not-exist", "provider-x", "pending", nil, nil); err != paymentdomain.ErrPaymentNotFound {
		t.Fatalf("err = %v, want ErrPaymentNotFound", err)
	}
}
