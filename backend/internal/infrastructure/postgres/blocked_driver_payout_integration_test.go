//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	pricingdomain "evik/backend/internal/domain/pricing"
	"evik/backend/internal/infrastructure/postgres"
	paymentuc "evik/backend/internal/usecase/payment"
)

// okPricingService is a no-op pricing service: payout flow never prices an order.
type okPricingService struct{}

func (okPricingService) CalculatePrice(context.Context, pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error) {
	return &pricingdomain.PriceCalculation{}, nil
}

// successProvider returns a succeeded payout, simulating YooKassa.
type successProvider struct{}

func (successProvider) CreatePayment(context.Context, paymentuc.ProviderPaymentRequest) (*paymentuc.ProviderPaymentResponse, error) {
	return &paymentuc.ProviderPaymentResponse{}, nil
}

func (successProvider) GetPayment(context.Context, string) (*paymentuc.ProviderPaymentResponse, error) {
	return &paymentuc.ProviderPaymentResponse{}, nil
}

func (successProvider) CreatePayout(_ context.Context, _ paymentuc.ProviderPayoutRequest) (*paymentuc.ProviderPayoutResponse, error) {
	return &paymentuc.ProviderPayoutResponse{ID: "provider-payout-blocked-driver", Status: "succeeded"}, nil
}

type seqIDGenerator struct{ n int }

func (g *seqIDGenerator) NewID() string {
	g.n++
	return fmt.Sprintf("id-%d", g.n)
}

// seedBlockedDriverWithMoney seeds a driver whose verification is 'blocked'
// together with a funded wallet and a default payout method.
func seedBlockedDriverWithMoney(t *testing.T, db *sql.DB, driverID string) {
	t.Helper()
	seedDriverWithVerification(t, db, driverID, "blocked", nil)
	if _, err := db.Exec(`
INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
VALUES ($1, $2, 850000, 0, 0, 'RUB', NOW(), NOW())
ON CONFLICT (driver_id) DO UPDATE SET available_balance = 850000, updated_at = NOW()`,
		"wallet_"+driverID, driverID); err != nil {
		t.Fatalf("insert wallet: %v", err)
	}
	if _, err := db.Exec(`
INSERT INTO driver_payout_methods (id, driver_id, provider_recipient_id, type, masked_value, is_default, status, created_at)
VALUES ($1, $2, 'recipient-blocked', 'card', '****1234', TRUE, 'active', NOW())
ON CONFLICT (id) DO NOTHING`, "pm-"+driverID, driverID); err != nil {
		t.Fatalf("insert payout method: %v", err)
	}
}

// TestRequestDriverPayout_BlockedDriverAllowed proves the product decision:
// a driver whose verification status is 'blocked' keeps full access to
// withdrawing earned money — nothing in the payout path gates on verification.
func TestRequestDriverPayout_BlockedDriverAllowed(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	driverID := "driver-blocked-payout"
	seedBlockedDriverWithMoney(t, db, driverID)

	uc := paymentuc.NewFinanceUseCase(
		postgres.NewPaymentRepository(db),
		postgres.NewOrderRepository(db),
		postgres.NewDriverRepository(db, nil),
		okPricingService{},
		successProvider{},
		postgres.NewSettingsRepository(db),
		integrationClock{now: time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)},
		&seqIDGenerator{},
		600,
		1,
		integrationPublisher{},
	)

	payout, err := uc.RequestDriverPayout(ctx, driverID, 850000, "idem-blocked-driver")
	if err != nil {
		t.Fatalf("blocked driver payout must not be gated, got err: %v", err)
	}
	if payout == nil || payout.ID == "" {
		t.Fatal("expected a created payout")
	}
	if payout.Status != "paid" {
		t.Fatalf("payout status = %q, want 'paid' (provider succeeded)", payout.Status)
	}

	var status string
	var available int64
	if err := db.QueryRow(`SELECT available_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&available); err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if available != 0 {
		t.Fatalf("available_balance = %d, want 0 after paid payout of 850000", available)
	}
	if err := db.QueryRow(`SELECT status FROM driver_verifications WHERE user_id = $1`, driverID).Scan(&status); err != nil {
		t.Fatalf("query verification: %v", err)
	}
	if status != "blocked" {
		t.Fatalf("verification status = %q, want 'blocked' (payout must not unblock the driver)", status)
	}
}

// TestRequestDriverPayout_BlockedDriverInsufficientFunds ensures the wallet
// balance guard still applies to a blocked driver (only money gates remain).
func TestRequestDriverPayout_BlockedDriverInsufficientFunds(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	driverID := "driver-blocked-poor"
	seedBlockedDriverWithMoney(t, db, driverID)

	uc := paymentuc.NewFinanceUseCase(
		postgres.NewPaymentRepository(db),
		postgres.NewOrderRepository(db),
		postgres.NewDriverRepository(db, nil),
		okPricingService{},
		successProvider{},
		postgres.NewSettingsRepository(db),
		integrationClock{now: time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)},
		&seqIDGenerator{},
		600,
		1,
		integrationPublisher{},
	)

	_, err := uc.RequestDriverPayout(ctx, driverID, 8500000, "idem-blocked-poor")
	if err == nil {
		t.Fatal("payout above balance must be rejected even for a blocked driver")
	}
}
