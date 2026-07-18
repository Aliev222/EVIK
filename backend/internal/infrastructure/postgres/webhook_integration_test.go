//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	pricingdomain "evik/backend/internal/domain/pricing"
	"evik/backend/internal/domain/settings"
	"evik/backend/internal/infrastructure/postgres"
	paymentuc "evik/backend/internal/usecase/payment"
)

// --- fakes ---

type webhookOrderRepo struct {
	orders      map[string]*orderdomain.Order
	updateCalls int
}

func (r *webhookOrderRepo) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	if r.orders != nil {
		if o, ok := r.orders[id]; ok {
			return o, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (r *webhookOrderRepo) Update(_ context.Context, ord *orderdomain.Order) error {
	r.updateCalls++
	if r.orders != nil {
		r.orders[ord.ID] = ord
	}
	return nil
}

func (webhookOrderRepo) GetByOrderKey(context.Context, string) (*orderdomain.Order, error) { return nil, sql.ErrNoRows }
func (webhookOrderRepo) Create(context.Context, *orderdomain.Order) error                  { return nil }
func (webhookOrderRepo) AcceptOrder(context.Context, string, string) (*orderdomain.Order, error) {
	return nil, nil
}
func (webhookOrderRepo) ListByStatus(context.Context, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (webhookOrderRepo) ListAdminOrders(context.Context, orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error) {
	return nil, 0, nil
}
func (webhookOrderRepo) GetAdminOrderDetails(context.Context, string) (*orderdomain.AdminOrderDetails, error) {
	return nil, nil
}

type webhookSettingsRepo struct {
	settings []settings.Setting
}

func (s *webhookSettingsRepo) List(_ context.Context) ([]settings.Setting, error) {
	return s.settings, nil
}
func (webhookSettingsRepo) Upsert(context.Context, string, any) error { return nil }

type webhookPricingService struct{}

func (webhookPricingService) CalculatePrice(_ context.Context, _ pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error) {
	return &pricingdomain.PriceCalculation{TotalPrice: 500000}, nil
}

type webhookProvider struct {
	getPaymentCalls int
}

type failProvider struct{}

func (*failProvider) GetPayment(_ context.Context, id string) (*paymentuc.ProviderPaymentResponse, error) {
	return nil, sql.ErrNoRows
}
func (*failProvider) CreatePayment(context.Context, paymentuc.ProviderPaymentRequest) (*paymentuc.ProviderPaymentResponse, error) {
	return nil, nil
}
func (*failProvider) CreatePayout(context.Context, paymentuc.ProviderPayoutRequest) (*paymentuc.ProviderPayoutResponse, error) {
	return nil, nil
}

type retryProvider struct {
	getPaymentCalls int
}

func (p *retryProvider) GetPayment(_ context.Context, id string) (*paymentuc.ProviderPaymentResponse, error) {
	p.getPaymentCalls++
	if p.getPaymentCalls == 1 {
		return nil, sql.ErrNoRows
	}
	return &paymentuc.ProviderPaymentResponse{ID: id, Status: "succeeded", Paid: true}, nil
}
func (*retryProvider) CreatePayment(context.Context, paymentuc.ProviderPaymentRequest) (*paymentuc.ProviderPaymentResponse, error) {
	return &paymentuc.ProviderPaymentResponse{ID: "pp-1", Status: "pending"}, nil
}
func (*retryProvider) CreatePayout(context.Context, paymentuc.ProviderPayoutRequest) (*paymentuc.ProviderPayoutResponse, error) {
	return &paymentuc.ProviderPayoutResponse{ID: "po-1", Status: "succeeded"}, nil
}

func (p *webhookProvider) CreatePayment(context.Context, paymentuc.ProviderPaymentRequest) (*paymentuc.ProviderPaymentResponse, error) {
	return &paymentuc.ProviderPaymentResponse{ID: "pp-1", Status: "pending"}, nil
}
func (p *webhookProvider) GetPayment(_ context.Context, id string) (*paymentuc.ProviderPaymentResponse, error) {
	p.getPaymentCalls++
	return &paymentuc.ProviderPaymentResponse{ID: id, Status: "succeeded", Paid: true}, nil
}
func (p *webhookProvider) CreatePayout(context.Context, paymentuc.ProviderPayoutRequest) (*paymentuc.ProviderPayoutResponse, error) {
	return &paymentuc.ProviderPayoutResponse{ID: "po-1", Status: "succeeded"}, nil
}

type webhookClock struct{ now time.Time }

func (c webhookClock) Now() time.Time { return c.now }

type webhookIDGen struct{}

func (webhookIDGen) NewID() string { return "gen-id" }

type releaseStore struct{}

func (releaseStore) ReleaseOrder(_ context.Context, _, _ string, _ time.Time) error { return nil }

func strPtr(s string) *string { return &s }

// --- test ---

// TestWebhook_CurrentBehavior_Success verifies that the current webhook handler
// (before transactional refactoring) correctly processes a payment.succeeded
// event end-to-end: payment updated, wallet credited, order completed,
// webhook marked processed. This test establishes the baseline behavior
// that the refactored code must preserve.
func TestWebhook_CurrentBehavior_Success(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	// --- seed ---
	seedUser(t, db, "client-1", "client")
	seedUser(t, db, "driver-1", "driver")
	seedDriver(t, db, "driver-1")

	_, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'card', $4, $4)`,
		"order-1", "client-1", "driver-1", now)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
			amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'p-1', 'card', 'order', 500000, 'RUB', 'pending', 'ik-1', $4, $4)`,
		"payment-1", "order-1", "client-1", now)
	if err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', $3, $3)`,
		"wallet_driver-1", "driver-1", now)
	if err != nil {
		t.Fatalf("insert driver wallet: %v", err)
	}

	// --- usecase ---
	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-1": {
				ID:            "order-1",
				UserID:        "client-1",
				DriverID:      strPtr("driver-1"),
				Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType:  orderdomain.TowTruckWinch,
				Status:        orderdomain.StatusAwaitingPayment,
				PriceTotal:    500000,
				PaymentMethod: "card",
				CreatedAt:     now,
				UpdatedAt:     now,
			},
		},
	}
	settingsRepo := &webhookSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "15"},
		},
	}
	provider := &webhookProvider{}

	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, orderRepo, releaseStore{}, webhookPricingService{}, provider, settingsRepo, webhookClock{now: now}, webhookIDGen{}, 600, 10000)

	// --- execute ---
	payload, _ := json.Marshal(map[string]any{
		"event": "payment.succeeded",
		"object": map[string]any{
			"id":     "p-1",
			"status": "succeeded",
			"paid":   true,
			"metadata": map[string]string{
				"purpose":  "order",
				"order_id": "order-1",
			},
		},
	})

	verifier := paymentuc.NewYooKassaVerifier()
	err = financeUC.HandleProviderWebhook(ctx, verifier, payload)
	if err != nil {
		t.Fatalf("HandleProviderWebhook failed: %v", err)
	}

	// --- assertions ---

	// 1. payment_webhooks row with processed=TRUE
	var processed bool
	var processedAt *time.Time
	err = db.QueryRowContext(ctx, `SELECT processed, processed_at FROM payment_webhooks WHERE id = $1`, "payment.succeeded:p-1").Scan(&processed, &processedAt)
	if err != nil {
		t.Fatalf("query payment_webhooks: %v", err)
	}
	if !processed {
		t.Error("payment_webhooks.processed = false, want true")
	}
	if processedAt == nil {
		t.Error("payment_webhooks.processed_at is NULL, want timestamp")
	}

	// 2. payment updated to succeeded
	var payStatus string
	err = db.QueryRowContext(ctx, `SELECT status FROM payments WHERE id = $1`, "payment-1").Scan(&payStatus)
	if err != nil {
		t.Fatalf("query payment: %v", err)
	}
	if payStatus != "succeeded" {
		t.Errorf("payment status = %q, want 'succeeded'", payStatus)
	}

	// 3. order financial status completed, financially_completed_at set
	var finStatus string
	var finCompletedAt *time.Time
	err = db.QueryRowContext(ctx, `SELECT financial_status, financially_completed_at FROM orders WHERE id = $1`, "order-1").Scan(&finStatus, &finCompletedAt)
	if err != nil {
		t.Fatalf("query order financial: %v", err)
	}
	if finStatus != "completed" {
		t.Errorf("order financial_status = %q, want 'completed'", finStatus)
	}
	if finCompletedAt == nil {
		t.Error("order financially_completed_at is NULL, want timestamp")
	}

	// 4. wallet transactions created (order_income + debt_repayment for card)
	var txCount int
	err = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE wallet_id = $1`, "wallet_driver-1").Scan(&txCount)
	if err != nil {
		t.Fatalf("count wallet_transactions: %v", err)
	}
	if txCount == 0 {
		t.Errorf("wallet_transactions count = 0, expected at least 1")
	}

	// 5. wallet pending_balance = price_total - 15% commission = 425000 kopecks
	var pending int64
	err = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-1").Scan(&pending)
	if err != nil {
		t.Fatalf("query driver_wallets: %v", err)
	}
	if pending != 425000 {
		t.Errorf("pending_balance = %d, want 425000", pending)
	}

	// 6. orderRepo.Update was called (status transition to completed)
	if orderRepo.updateCalls != 1 {
		t.Errorf("orderRepo.Update calls = %d, want 1", orderRepo.updateCalls)
	}

	// 7. GetPayment called once (provider-side verification)
	if provider.getPaymentCalls != 1 {
		t.Errorf("GetPayment calls = %d, want 1", provider.getPaymentCalls)
	}
}

// TestWebhook_MidTxFailure_RollsBack verifies that when provider-side
// verification fails inside WithWebhookTx, the transaction is rolled back
// and no webhook row or side effects remain.
func TestWebhook_MidTxFailure_RollsBack(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-f", "client")
	seedUser(t, db, "driver-f", "driver")
	seedDriver(t, db, "driver-f")

	_, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'accepted', 500000, 'card', $4, $4)`,
		"order-f", "client-f", "driver-f", now)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
			amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'p-fail', 'card', 'order', 500000, 'RUB', 'pending', 'ik-f', $4, $4)`,
		"payment-f", "order-f", "client-f", now)
	if err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', $3, $3)`,
		"wallet_driver-f", "driver-f", now)
	if err != nil {
		t.Fatalf("insert driver wallet: %v", err)
	}

	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, &webhookOrderRepo{}, releaseStore{}, webhookPricingService{}, &failProvider{}, &webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}}, webhookClock{now: now}, webhookIDGen{}, 600, 10000)

	payload, _ := json.Marshal(map[string]any{
		"event": "payment.succeeded",
		"object": map[string]any{
			"id":     "p-fail",
			"status": "succeeded",
			"paid":   true,
			"metadata": map[string]string{
				"purpose":  "order",
				"order_id": "order-f",
			},
		},
	})

	verifier := paymentuc.NewYooKassaVerifier()
	err = financeUC.HandleProviderWebhook(ctx, verifier, payload)
	if err == nil {
		t.Fatal("expected error from failing provider, got nil")
	}

	// payment_webhooks row should NOT exist (tx rolled back)
	var webhookCount int
	_ = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_webhooks WHERE id = $1`, "payment.succeeded:p-fail").Scan(&webhookCount)
	if webhookCount != 0 {
		t.Errorf("payment_webhooks rows = %d, want 0 (tx rolled back)", webhookCount)
	}

	// payment status should remain 'pending'
	var payStatus string
	_ = db.QueryRowContext(ctx, `SELECT status FROM payments WHERE id = $1`, "payment-f").Scan(&payStatus)
	if payStatus != "pending" {
		t.Errorf("payment status = %q, want 'pending' (unchanged)", payStatus)
	}

	// wallet balance should remain 0
	var pending int64
	_ = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-f").Scan(&pending)
	if pending != 0 {
		t.Errorf("pending_balance = %d, want 0", pending)
	}
}

// TestWebhook_RetryAfterFailure verifies that a webhook that first fails
// (provider error) can be retried successfully — the second attempt processes
// the event and marks it processed.
func TestWebhook_RetryAfterFailure(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-rf", "client")
	seedUser(t, db, "driver-rf", "driver")
	seedDriver(t, db, "driver-rf")

	_, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'card', $4, $4)`,
		"order-rf", "client-rf", "driver-rf", now)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
			amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'p-rf', 'card', 'order', 500000, 'RUB', 'pending', 'ik-rf', $4, $4)`,
		"payment-rf", "order-rf", "client-rf", now)
	if err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', $3, $3)`,
		"wallet_driver-rf", "driver-rf", now)
	if err != nil {
		t.Fatalf("insert driver wallet: %v", err)
	}

	retryProv := &retryProvider{}
	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-rf": {
				ID: "order-rf", UserID: "client-rf", DriverID: strPtr("driver-rf"),
				Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Dropoff: orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType: orderdomain.TowTruckWinch, Status: orderdomain.StatusAwaitingPayment,
				PriceTotal: 500000, PaymentMethod: "card", CreatedAt: now, UpdatedAt: now,
			},
		},
	}
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, orderRepo, releaseStore{}, webhookPricingService{}, retryProv, &webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}}, webhookClock{now: now}, webhookIDGen{}, 600, 10000)

	payload, _ := json.Marshal(map[string]any{
		"event": "payment.succeeded",
		"object": map[string]any{
			"id":     "p-rf",
			"status": "succeeded",
			"paid":   true,
			"metadata": map[string]string{
				"purpose":  "order",
				"order_id": "order-rf",
			},
		},
	})

	verifier := paymentuc.NewYooKassaVerifier()

	// --- first attempt: fail ---
	err = financeUC.HandleProviderWebhook(ctx, verifier, payload)
	if err == nil {
		t.Fatal("expected error on first attempt, got nil")
	}

	// --- second attempt: succeed ---
	err = financeUC.HandleProviderWebhook(ctx, verifier, payload)
	if err != nil {
		t.Fatalf("second attempt failed: %v", err)
	}

	// payment_webhooks processed
	var processed bool
	_ = db.QueryRowContext(ctx, `SELECT processed FROM payment_webhooks WHERE id = $1`, "payment.succeeded:p-rf").Scan(&processed)
	if !processed {
		t.Error("payment_webhooks.processed = false after second attempt, want true")
	}

	// payment status updated
	var payStatus string
	_ = db.QueryRowContext(ctx, `SELECT status FROM payments WHERE id = $1`, "payment-rf").Scan(&payStatus)
	if payStatus != "succeeded" {
		t.Errorf("payment status = %q, want 'succeeded'", payStatus)
	}

	// wallet credited
	var pending int64
	_ = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-rf").Scan(&pending)
	if pending != 425000 {
		t.Errorf("pending_balance = %d, want 425000", pending)
	}
}

// TestWebhook_RetryAfterSuccess verifies that processing the same event twice
// is idempotent — the second call returns nil without re-applying side effects.
func TestWebhook_RetryAfterSuccess(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	now := time.Date(2026, 6, 15, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-rs", "client")
	seedUser(t, db, "driver-rs", "driver")
	seedDriver(t, db, "driver-rs")

	_, err := db.ExecContext(ctx, `
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, created_at, updated_at)
		VALUES ($1, $2, $3, 55.75, 37.62, 55.76, 37.63, 'winch', 'awaiting_payment', 500000, 'card', $4, $4)`,
		"order-rs", "client-rs", "driver-rs", now)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO payments (id, order_id, user_id, provider, provider_payment_id, payment_method, purpose,
			amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'p-rs', 'card', 'order', 500000, 'RUB', 'pending', 'ik-rs', $4, $4)`,
		"payment-rs", "order-rs", "client-rs", now)
	if err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', $3, $3)`,
		"wallet_driver-rs", "driver-rs", now)
	if err != nil {
		t.Fatalf("insert driver wallet: %v", err)
	}

	orderRepo := &webhookOrderRepo{
		orders: map[string]*orderdomain.Order{
			"order-rs": {
				ID: "order-rs", UserID: "client-rs", DriverID: strPtr("driver-rs"),
				Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Dropoff: orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType: orderdomain.TowTruckWinch, Status: orderdomain.StatusAwaitingPayment,
				PriceTotal: 500000, PaymentMethod: "card", CreatedAt: now, UpdatedAt: now,
			},
		},
	}
	provider := &webhookProvider{}
	paymentRepo := postgres.NewPaymentRepository(db)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, orderRepo, releaseStore{}, webhookPricingService{}, provider, &webhookSettingsRepo{settings: []settings.Setting{{Key: "commission_percent", Value: "15"}}}, webhookClock{now: now}, webhookIDGen{}, 600, 10000)

	payload, _ := json.Marshal(map[string]any{
		"event": "payment.succeeded",
		"object": map[string]any{
			"id":     "p-rs",
			"status": "succeeded",
			"paid":   true,
			"metadata": map[string]string{
				"purpose":  "order",
				"order_id": "order-rs",
			},
		},
	})

	verifier := paymentuc.NewYooKassaVerifier()

	// --- first call: succeed ---
	err = financeUC.HandleProviderWebhook(ctx, verifier, payload)
	if err != nil {
		t.Fatalf("first call: %v", err)
	}

	// record side effect counters
	var pendingAfterFirst int64
	_ = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-rs").Scan(&pendingAfterFirst)

	// --- second call: duplicate, should be idempotent ---
	err = financeUC.HandleProviderWebhook(ctx, verifier, payload)
	if err != nil {
		t.Fatalf("duplicate call: %v", err)
	}

	// pending_balance unchanged
	var pendingAfterSecond int64
	_ = db.QueryRowContext(ctx, `SELECT pending_balance FROM driver_wallets WHERE id = $1`, "wallet_driver-rs").Scan(&pendingAfterSecond)
	if pendingAfterSecond != pendingAfterFirst {
		t.Errorf("pending_balance changed from %d to %d after duplicate", pendingAfterFirst, pendingAfterSecond)
	}

	// GetPayment should only have been called once (second call short-circuits at CheckProcessed)
	if provider.getPaymentCalls != 1 {
		t.Errorf("GetPayment calls = %d, want 1", provider.getPaymentCalls)
	}
}

// TestWebhook_YooKassaVerifier_ForgedIP verifies that the YooKassaVerifier
// rejects requests from IPs outside the YooKassa allowlist.
func TestWebhook_YooKassaVerifier_ForgedIP(t *testing.T) {
	verifier := paymentuc.NewYooKassaVerifier()

	tests := []struct {
		name    string
		remote  string
		xrip    string
		wantErr bool
	}{
		{name: "non-yookassa ipv4", remote: "203.0.113.1:12345", wantErr: true},
		{name: "yookassa ipv4", remote: "185.71.76.1:443", wantErr: false},
		{name: "forged x-real-ip", remote: "203.0.113.1:12345", xrip: "203.0.113.2", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := makeHTTPRequest(tt.remote, tt.xrip)
			err := verifier.Verify(req, nil)
			if tt.wantErr && err == nil {
				t.Error("expected error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
}

// makeHTTPRequest creates a minimal *http.Request with the given RemoteAddr
// and optional X-Real-IP header for verifier testing.
func makeHTTPRequest(remoteAddr, xRealIP string) *http.Request {
	req := &http.Request{RemoteAddr: remoteAddr}
	if xRealIP != "" {
		req.Header = http.Header{}
		req.Header.Set("X-Real-IP", xRealIP)
	}
	return req
}


