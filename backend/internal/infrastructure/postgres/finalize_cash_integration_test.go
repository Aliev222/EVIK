//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	"evik/backend/internal/infrastructure/postgres"
	orderuc "evik/backend/internal/usecase/order"
	paymentuc "evik/backend/internal/usecase/payment"
)

// finalizeLogger is a silent Logger for FinalizeOrderUseCase.
type finalizeLogger struct{}

func (finalizeLogger) Info(string, ...any)         {}
func (finalizeLogger) Error(string, error, ...any) {}

// recordPublisher captures published events synchronously.
type recordPublisher struct {
	events []orderdomain.Event
}

func (p *recordPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	p.events = append(p.events, event)
	return nil
}

func (p *recordPublisher) contains(t orderdomain.EventType) bool {
	for _, e := range p.events {
		if e.Type == t {
			return true
		}
	}
	return false
}

// succeededCardProvider returns succeeded at payment creation (mirrors a card
// that is paid immediately, no 3DS).
type succeededCardProvider struct{}

func (*succeededCardProvider) CreatePayment(context.Context, paymentuc.ProviderPaymentRequest) (*paymentuc.ProviderPaymentResponse, error) {
	return &paymentuc.ProviderPaymentResponse{ID: "pp-card-1", Status: "succeeded", Paid: true}, nil
}
func (*succeededCardProvider) GetPayment(_ context.Context, id string) (*paymentuc.ProviderPaymentResponse, error) {
	return &paymentuc.ProviderPaymentResponse{ID: id, Status: "succeeded", Paid: true}, nil
}
func (*succeededCardProvider) CreatePayout(context.Context, paymentuc.ProviderPayoutRequest) (*paymentuc.ProviderPayoutResponse, error) {
	return nil, nil
}

func seedCashOrderForFinalize(t *testing.T, db *sql.DB, orderID, driverID, userID string, price int64, now time.Time) {
	t.Helper()
	_, err := db.Exec(`
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'in_progress', $4, 'cash', $5, $5)`,
		orderID, userID, driverID, price, now)
	if err != nil {
		t.Fatalf("insert cash order: %v", err)
	}
	_, err = db.Exec(`UPDATE drivers SET status = 'busy', current_order_id = $1 WHERE id = $2`, orderID, driverID)
	if err != nil {
		t.Fatalf("mark driver busy: %v", err)
	}
}

func newFinalizeUCForIntegration(db *sql.DB, now time.Time, commissionPct string) (*orderuc.FinalizeOrderUseCase, *recordPublisher) {
	orderRepo := postgres.NewOrderRepository(db)
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(
		paymentRepo,
		orderRepo,
		releaseStore{},
		webhookPricingService{},
		&webhookProvider{},
		&webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: commissionPct}}},
		webhookClock{now: now},
		webhookIDGen{},
		600,
		10000,
		nil,
	)
	publisher := &recordPublisher{}
	uc := orderuc.NewFinalizeOrderUseCase(orderRepo, paymentRepo, financeUC, 600, publisher, nil, webhookClock{now: now}, finalizeLogger{})
	return uc, publisher
}

// TestFinalizeCash_AutoCompletesWithExactDebt is the end-to-end cash contract:
// driver finalize → the order is immediately completed and financially closed,
// the driver is released back online, and the wallet carries exactly 15% of the
// order as commission debt. One cash_commission_debt wallet transaction is
// recorded.
func TestFinalizeCash_AutoCompletesWithExactDebt(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-fc", "client")
	seedUser(t, db, "driver-fc", "driver")
	seedDriver(t, db, "driver-fc")
	seedCashOrderForFinalize(t, db, "order-fc", "driver-fc", "client-fc", 500000, now)
	seedWallet(t, db, "driver-fc", 0, 0, 0)

	uc, publisher := newFinalizeUCForIntegration(db, now, "15")

	ord, err := uc.Execute(ctx, orderuc.FinalizeOrderInput{OrderID: "order-fc", DriverID: "driver-fc", FinalPrice: 500000})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusCompleted {
		t.Fatalf("status = %q, want %q (cash auto-complete)", ord.Status, orderdomain.StatusCompleted)
	}
	if !publisher.contains(orderdomain.EventCompleted) {
		t.Fatalf("events = %+v, want a completed event published", publisher.events)
	}

	// order: completed + financially closed with exact split
	var status, finStatus string
	var commission, driverAmount int64
	var finCompleted sql.NullTime
	err = db.QueryRowContext(ctx, `SELECT status, financial_status, commission_amount, driver_amount, financially_completed_at FROM orders WHERE id = $1`, "order-fc").Scan(&status, &finStatus, &commission, &driverAmount, &finCompleted)
	if err != nil {
		t.Fatalf("query order: %v", err)
	}
	if status != string(orderdomain.StatusCompleted) {
		t.Errorf("order status = %q, want completed", status)
	}
	if finStatus != "completed" {
		t.Errorf("financial_status = %q, want completed", finStatus)
	}
	if commission != 75000 {
		t.Errorf("commission_amount = %d, want 75000 (15%% of 500000)", commission)
	}
	if driverAmount != 425000 {
		t.Errorf("driver_amount = %d, want 425000", driverAmount)
	}
	if !finCompleted.Valid {
		t.Error("financially_completed_at is NULL for a completed order (completion guard)")
	}

	// driver: released back online, no current order
	var cur sql.NullString
	var dstatus string
	err = db.QueryRowContext(ctx, `SELECT current_order_id, status FROM drivers WHERE id = $1`, "driver-fc").Scan(&cur, &dstatus)
	if err != nil {
		t.Fatalf("query driver: %v", err)
	}
	if cur.Valid {
		t.Errorf("driver current_order_id = %q, want NULL (driver must be freed)", cur.String)
	}
	if dstatus != "online" {
		t.Errorf("driver status = %q, want online", dstatus)
	}

	// wallet: exact 15% debt
	var debt int64
	err = db.QueryRowContext(ctx, `SELECT debt_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-fc").Scan(&debt)
	if err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if debt != 75000 {
		t.Errorf("wallet debt_balance = %d, want 75000 (15%% of 500000)", debt)
	}

	// exactly one cash_commission_debt transaction
	var txCount int
	err = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE type = 'cash_commission_debt' AND order_id = $1`, "order-fc").Scan(&txCount)
	if err != nil {
		t.Fatalf("count debt transactions: %v", err)
	}
	if txCount != 1 {
		t.Errorf("cash_commission_debt tx count = %d, want 1", txCount)
	}
}

// TestFinalizeCash_SubscriptionWaivesDebt verifies the subscription rule: with
// an active driver subscription the cash commission is 0% — the order completes
// and NO debt is recorded.
func TestFinalizeCash_SubscriptionWaivesDebt(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-fs", "client")
	seedUser(t, db, "driver-fs", "driver")
	seedDriver(t, db, "driver-fs")
	seedCashOrderForFinalize(t, db, "order-fs", "driver-fs", "client-fs", 500000, now)
	seedWallet(t, db, "driver-fs", 0, 0, 0)

	// active subscription (pro_day)
	_, err := db.Exec(`
		INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
			amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, NULL, $2, 'yookassa', 'sub-pp', 'card', 'subscription', 50000, 'RUB', 'succeeded', 'sub-idem', $3, $3)`,
		"sub-payment", "driver-fs", now)
	if err != nil {
		t.Fatalf("insert subscription payment: %v", err)
	}
	_, err = db.Exec(`
		INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
		VALUES ($1, $2, 'pro_day', $3, 50000, 'RUB', 'active', NOW(), NOW() + INTERVAL '30 days', NOW(), NOW())`,
		"sub-1", "driver-fs", "sub-payment")
	if err != nil {
		t.Fatalf("insert subscription: %v", err)
	}

	uc, _ := newFinalizeUCForIntegration(db, now, "15")

	ord, err := uc.Execute(ctx, orderuc.FinalizeOrderInput{OrderID: "order-fs", DriverID: "driver-fs", FinalPrice: 500000})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusCompleted {
		t.Fatalf("status = %q, want completed", ord.Status)
	}

	var debt int64
	var commission int64
	err = db.QueryRowContext(ctx, `SELECT debt_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-fs").Scan(&debt)
	if err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if debt != 0 {
		t.Errorf("wallet debt_balance = %d, want 0 (subscription waives the commission)", debt)
	}
	err = db.QueryRowContext(ctx, `SELECT commission_amount FROM orders WHERE id = $1`, "order-fs").Scan(&commission)
	if err != nil {
		t.Fatalf("query order: %v", err)
	}
	if commission != 0 {
		t.Errorf("commission_amount = %d, want 0 with active subscription", commission)
	}
}

// TestFinalizeCash_RepeatedFinalizeHasNoDoubleDebt verifies idempotency end to
// end: a repeated finalize is rejected by the status guard, and even a direct
// second settlement call with the same idempotency key cannot double the debt.
func TestFinalizeCash_RepeatedFinalizeHasNoDoubleDebt(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-fi", "client")
	seedUser(t, db, "driver-fi", "driver")
	seedDriver(t, db, "driver-fi")
	seedCashOrderForFinalize(t, db, "order-fi", "driver-fi", "client-fi", 500000, now)
	seedWallet(t, db, "driver-fi", 0, 0, 0)

	uc, _ := newFinalizeUCForIntegration(db, now, "15")

	if _, err := uc.Execute(ctx, orderuc.FinalizeOrderInput{OrderID: "order-fi", DriverID: "driver-fi", FinalPrice: 500000}); err != nil {
		t.Fatalf("first finalize: %v", err)
	}

	// repeated driver finalize → rejected, no extra settlement
	if _, err := uc.Execute(ctx, orderuc.FinalizeOrderInput{OrderID: "order-fi", DriverID: "driver-fi", FinalPrice: 500000}); !errors.Is(err, orderdomain.ErrInvalidTransition) {
		t.Fatalf("second finalize err = %v, want ErrInvalidTransition", err)
	}

	// belt-and-braces: bypass the status guard and settle directly with the
	// same idempotency key — the repository must short-circuit.
	paymentRepo := postgres.NewPaymentRepository(db)
	if err := paymentRepo.CompleteOrderFinancially(ctx, "order-fi", "complete_order:order-fi", 600, 15); err != nil {
		t.Fatalf("direct settlement retry: %v", err)
	}

	var debt int64
	var txCount int
	err := db.QueryRowContext(ctx, `SELECT debt_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-fi").Scan(&debt)
	if err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if debt != 75000 {
		t.Errorf("wallet debt_balance = %d, want 75000 (no double debt)", debt)
	}
	err = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE type = 'cash_commission_debt' AND order_id = $1`, "order-fi").Scan(&txCount)
	if err != nil {
		t.Fatalf("count debt transactions: %v", err)
	}
	if txCount != 1 {
		t.Errorf("cash_commission_debt tx count = %d, want 1 (idempotent)", txCount)
	}
}

// TestFinalizeCard_AwaitingPaymentThenClientPayRepaysDebt verifies the card
// flow is unchanged and financially correct: finalize leaves the order in
// awaiting_payment with the driver still busy; after the client pays by card
// the order completes, existing debt is repaid out of the driver's earnings and
// the remainder sits in pending.
func TestFinalizeCard_AwaitingPaymentThenClientPayRepaysDebt(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-fcd", "client")
	seedUser(t, db, "driver-fcd", "driver")
	seedDriver(t, db, "driver-fcd")
	// pre-existing debt of 150000 (e.g. from an earlier cash order)
	seedWallet(t, db, "driver-fcd", 0, 0, 150000)

	_, err := db.Exec(`
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'in_progress', 1000000, 'card', $4, $4)`,
		"order-fcd", "client-fcd", "driver-fcd", now)
	if err != nil {
		t.Fatalf("insert card order: %v", err)
	}
	_, err = db.Exec(`UPDATE drivers SET status = 'busy', current_order_id = $1 WHERE id = $2`, "order-fcd", "driver-fcd")
	if err != nil {
		t.Fatalf("mark driver busy: %v", err)
	}

	orderRepo := postgres.NewOrderRepository(db)
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(
		paymentRepo, orderRepo, releaseStore{}, webhookPricingService{}, &succeededCardProvider{},
		&webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}},
		webhookClock{now: now}, webhookIDGen{}, 600, 10000, nil,
	)
	uc := orderuc.NewFinalizeOrderUseCase(orderRepo, paymentRepo, financeUC, 600, &recordPublisher{}, nil, webhookClock{now: now}, finalizeLogger{})

	// 1) finalize → awaiting_payment, driver stays busy, wallet untouched
	ord, err := uc.Execute(ctx, orderuc.FinalizeOrderInput{OrderID: "order-fcd", DriverID: "driver-fcd", FinalPrice: 1000000})
	if err != nil {
		t.Fatalf("finalize: %v", err)
	}
	if ord.Status != orderdomain.StatusAwaitingPayment {
		t.Fatalf("status = %q, want awaiting_payment for card", ord.Status)
	}
	var cur sql.NullString
	var dstatus string
	err = db.QueryRowContext(ctx, `SELECT current_order_id, status FROM drivers WHERE id = $1`, "driver-fcd").Scan(&cur, &dstatus)
	if err != nil {
		t.Fatalf("query driver after finalize: %v", err)
	}
	if !cur.Valid || cur.String != "order-fcd" {
		t.Errorf("driver current_order_id = %v, want order-fcd (card order keeps driver busy)", cur)
	}
	if dstatus != "busy" {
		t.Errorf("driver status = %q, want busy", dstatus)
	}
	var debtBefore int64
	if err := db.QueryRowContext(ctx, `SELECT debt_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-fcd").Scan(&debtBefore); err != nil {
		t.Fatalf("query wallet before pay: %v", err)
	}
	if debtBefore != 150000 {
		t.Errorf("wallet debt before pay = %d, want 150000 (finalize must not touch money)", debtBefore)
	}

	// 2) client pays by card (paid at creation) → completed, debt repaid, remainder pending
	if _, err := financeUC.ConfirmOrderPayment(ctx, "client-fcd", "order-fcd"); err != nil {
		t.Fatalf("ConfirmOrderPayment: %v", err)
	}

	var status string
	var pending, debt int64
	err = db.QueryRowContext(ctx, `SELECT status FROM orders WHERE id = $1`, "order-fcd").Scan(&status)
	if err != nil {
		t.Fatalf("query order status: %v", err)
	}
	if status != string(orderdomain.StatusCompleted) {
		t.Errorf("order status = %q, want completed after card payment", status)
	}
	err = db.QueryRowContext(ctx, `SELECT pending_balance, debt_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-fcd").Scan(&pending, &debt)
	if err != nil {
		t.Fatalf("query wallet after pay: %v", err)
	}
	// commission 15% of 1000000 = 150000; driver amount 850000; existing debt 150000
	// repayment = min(850000, 150000) = 150000 → debt 0; pending = 850000 - 150000 = 700000
	if debt != 0 {
		t.Errorf("wallet debt after pay = %d, want 0 (repaid from earnings)", debt)
	}
	if pending != 700000 {
		t.Errorf("wallet pending = %d, want 700000 (850000 income minus 150000 debt)", pending)
	}

	// driver released after completion
	err = db.QueryRowContext(ctx, `SELECT status FROM drivers WHERE id = $1`, "driver-fcd").Scan(&dstatus)
	if err != nil {
		t.Fatalf("query driver after pay: %v", err)
	}
	if dstatus != "online" {
		t.Errorf("driver status = %q, want online after card completion", dstatus)
	}
}
