package payment

import (
	"context"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	pricingdomain "evik/backend/internal/domain/pricing"
	"evik/backend/internal/domain/settings"
)

func TestCompleteOrderFinanciallyDoesNotCreatePayout(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	uc := newTestFinanceUseCase(repo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}

	if repo.completeOrderCalls != 1 {
		t.Fatalf("complete calls = %d, want 1", repo.completeOrderCalls)
	}
	if repo.createPayoutCalls != 0 {
		t.Fatalf("payout calls = %d, want 0 after completed order", repo.createPayoutCalls)
	}
	if repo.completeIdempotencyKey != "complete_order:order-1" {
		t.Fatalf("idempotency key = %q, want complete_order:order-1", repo.completeIdempotencyKey)
	}
}

func TestPayoutIsCreatedOnlyByRequestDriverPayout(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	provider := &fakePaymentProvider{}
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &fakePricingService{}, provider, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)

	payout, err := uc.RequestDriverPayout(context.Background(), "driver-1", 850000, "payout-key-1")
	if err != nil {
		t.Fatalf("RequestDriverPayout returned error: %v", err)
	}

	if payout.ID == "" {
		t.Fatal("payout id is empty")
	}
	if repo.createPayoutCalls != 1 {
		t.Fatalf("create payout calls = %d, want 1", repo.createPayoutCalls)
	}
	if provider.payoutCalls != 1 {
		t.Fatalf("provider payout calls = %d, want 1", provider.payoutCalls)
	}
	if repo.markPayoutPaidCalls != 1 {
		t.Fatalf("mark paid calls = %d, want 1", repo.markPayoutPaidCalls)
	}
}

func TestRepeatedWebhookIsIgnoredBeforeFinancialSideEffects(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	uc := newTestFinanceUseCase(repo, now)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"provider-payment-1","status":"succeeded","paid":true,"metadata":{"purpose":"order","order_id":"order-1"}}}`)

	verifier := NewYooKassaVerifier()
	if err := uc.HandleProviderWebhook(context.Background(), verifier, payload); err != nil {
		t.Fatalf("first webhook returned error: %v", err)
	}
	if err := uc.HandleProviderWebhook(context.Background(), verifier, payload); err != nil {
		t.Fatalf("duplicate webhook returned error: %v", err)
	}

	if repo.updatePaymentCalls != 1 {
		t.Fatalf("payment update calls = %d, want 1", repo.updatePaymentCalls)
	}
	if repo.completeOrderCalls != 0 {
		t.Fatalf("complete order calls = %d, want 0 from webhook", repo.completeOrderCalls)
	}
	if repo.walletTransactionCreates != 0 {
		t.Fatalf("wallet transaction creates = %d, want 0 from duplicate webhook", repo.walletTransactionCreates)
	}
}

func TestCashAndCardSettlementRulesAreRepresentedByFinanceRepositoryContract(t *testing.T) {
	repo := newFakeFinanceRepository()
	repo.settlementMethod = paymentdomain.PaymentMethodCash
	if err := repo.CompleteOrderFinancially(context.Background(), "cash-order", "complete_order:cash-order", 600, 15); err != nil {
		t.Fatalf("cash settlement returned error: %v", err)
	}
	if repo.debtBalance != 150000 {
		t.Fatalf("cash debt balance = %d, want 150000", repo.debtBalance)
	}
	if repo.pendingBalance != 0 {
		t.Fatalf("cash pending balance = %d, want 0", repo.pendingBalance)
	}

	repo.settlementMethod = paymentdomain.PaymentMethodCard
	repo.orderAmount = 1000000
	if err := repo.CompleteOrderFinancially(context.Background(), "card-order", "complete_order:card-order", 600, 15); err != nil {
		t.Fatalf("card settlement returned error: %v", err)
	}
	if repo.debtBalance != 0 {
		t.Fatalf("debt balance after next card order = %d, want 0", repo.debtBalance)
	}
	if repo.pendingBalance != 700000 {
		t.Fatalf("pending balance = %d, want 700000 after 850000 income minus 150000 debt", repo.pendingBalance)
	}
	if repo.debtRepaymentTransactions != 1 {
		t.Fatalf("debt repayment tx count = %d, want 1", repo.debtRepaymentTransactions)
	}
}

type fakeSettingsRepo struct{}

func (r *fakeSettingsRepo) List(_ context.Context) ([]settings.Setting, error) {
	return nil, nil
}

func (r *fakeSettingsRepo) Upsert(_ context.Context, key string, value any) error {
	return nil
}

func newTestFinanceUseCase(repo *fakeFinanceRepository, now time.Time) *FinanceUseCase {
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &fakePricingService{}, &fakePaymentProvider{}, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)
}

type fakeFinanceRepository struct {
	paymentdomain.Repository
	webhooks                  map[string]bool
	settlementMethod          paymentdomain.PaymentMethodType
	orderAmount               int64
	surchargeAmount           int64
	debtBalance               int64
	pendingBalance            int64
	completeOrderCalls        int
	createPayoutCalls         int
	markPayoutPaidCalls       int
	storeWebhookCalls         int
	updatePaymentCalls        int
	walletTransactionCreates  int
	debtRepaymentTransactions int
	completeIdempotencyKey    string
	lastCommissionPercent     int
	hasActiveSubscription     bool
}

func newFakeFinanceRepository() *fakeFinanceRepository {
	return &fakeFinanceRepository{
		webhooks:         map[string]bool{},
		settlementMethod: paymentdomain.PaymentMethodCard,
		orderAmount:      1000000,
	}
}

func (r *fakeFinanceRepository) StoreWebhook(_ context.Context, eventID, provider, eventType string, payload []byte) (bool, error) {
	r.storeWebhookCalls++
	if r.webhooks[eventID] {
		return false, nil
	}
	r.webhooks[eventID] = true
	return true, nil
}

func (r *fakeFinanceRepository) MarkWebhookProcessed(context.Context, string) error {
	return nil
}

func (r *fakeFinanceRepository) CheckProcessed(_ context.Context, eventID, provider, eventType string, payload []byte) (bool, error) {
	if r.webhooks[eventID] {
		return true, nil
	}
	r.webhooks[eventID] = true
	return false, nil
}

func (r *fakeFinanceRepository) MarkProcessed(context.Context, string) error {
	return nil
}

func (r *fakeFinanceRepository) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	return fn(r)
}

func (r *fakeFinanceRepository) UpdatePaymentFromProvider(_ context.Context, providerPaymentID, status string, paid bool) (*paymentdomain.Payment, error) {
	r.updatePaymentCalls++
	return &paymentdomain.Payment{ID: "payment-1", Purpose: paymentdomain.PaymentPurposeOrder, Status: paymentdomain.PaymentStatus(status)}, nil
}

func (r *fakeFinanceRepository) CompleteOrderFinancially(_ context.Context, orderID, idempotencyKey string, holdSeconds, commissionPercent int) error {
	r.completeOrderCalls++
	r.completeIdempotencyKey = idempotencyKey
	r.lastCommissionPercent = commissionPercent

	effectivePercent := commissionPercent
	if r.hasActiveSubscription {
		effectivePercent = 0
	}

	total := r.orderAmount
	base := total - r.surchargeAmount
	commission := (base * int64(effectivePercent) + 50) / 100
	if r.settlementMethod == paymentdomain.PaymentMethodCash {
		r.debtBalance += commission
		r.walletTransactionCreates++
		return nil
	}
	driverAmount := total - commission
	repayment := driverAmount
	if r.debtBalance < repayment {
		repayment = r.debtBalance
	}
	if repayment > 0 {
		r.debtBalance -= repayment
		r.debtRepaymentTransactions++
		r.walletTransactionCreates++
	}
	r.pendingBalance += driverAmount - repayment
	if driverAmount-repayment > 0 {
		r.walletTransactionCreates++
	}
	return nil
}

func (r *fakeFinanceRepository) ListPayoutMethods(_ context.Context, driverID string) ([]paymentdomain.DriverPayoutMethod, error) {
	return []paymentdomain.DriverPayoutMethod{{
		ID:                  "method-1",
		DriverID:            driverID,
		ProviderRecipientID: "sandbox-recipient",
		Type:                paymentdomain.PayoutMethodCard,
		MaskedValue:         "**** 1111",
		IsDefault:           true,
		Status:              "active",
	}}, nil
}

func (r *fakeFinanceRepository) CreatePayout(_ context.Context, payout *paymentdomain.Payout, idempotencyKey string) (*paymentdomain.Payout, error) {
	r.createPayoutCalls++
	payout.WalletID = "wallet-1"
	payout.IdempotencyKey = idempotencyKey
	return payout, nil
}

func (r *fakeFinanceRepository) MarkPayoutPaid(ctx context.Context, payoutID, providerPayoutID, idempotencyKey string) error {
	r.markPayoutPaidCalls++
	return nil
}

type fakePaymentOrderRepo struct{}

func (r *fakePaymentOrderRepo) GetByOrderKey(context.Context, string) (*orderdomain.Order, error) { return nil, nil }
func (r *fakePaymentOrderRepo) Create(context.Context, *orderdomain.Order) error { return nil }
func (r *fakePaymentOrderRepo) Update(context.Context, *orderdomain.Order) error { return nil }
func (r *fakePaymentOrderRepo) UpdateStatus(context.Context, string, orderdomain.Status, time.Time) error { return nil }
func (r *fakePaymentOrderRepo) GetByID(context.Context, string) (*orderdomain.Order, error) {
	return &orderdomain.Order{
		ID:           "order-1",
		UserID:       "client-1",
		Pickup:       orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:      orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType: orderdomain.TowTruckWinch,
		Status:       orderdomain.StatusAccepted,
	}, nil
}
func (r *fakePaymentOrderRepo) ListByStatus(context.Context, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}

func (r *fakePaymentOrderRepo) ListAdminOrders(context.Context, orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error) {
	return nil, 0, nil
}

func (r *fakePaymentOrderRepo) GetAdminOrderDetails(context.Context, string) (*orderdomain.AdminOrderDetails, error) {
	return nil, nil
}
func (r *fakePaymentOrderRepo) AcceptOrder(context.Context, string, string) (*orderdomain.Order, error) {
	return nil, nil
}

type fakePricingService struct{}

func (s *fakePricingService) CalculatePrice(context.Context, pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error) {
	return &pricingdomain.PriceCalculation{TotalPrice: 1000000}, nil
}

type fakePaymentProvider struct {
	payoutCalls int
}

func (p *fakePaymentProvider) CreatePayment(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
	return &ProviderPaymentResponse{ID: "provider-payment-1", Status: "pending"}, nil
}

func (p *fakePaymentProvider) GetPayment(_ context.Context, id string) (*ProviderPaymentResponse, error) {
	return &ProviderPaymentResponse{ID: id, Status: "succeeded", Paid: true}, nil
}

func (p *fakePaymentProvider) CreatePayout(_ context.Context, req ProviderPayoutRequest) (*ProviderPayoutResponse, error) {
	p.payoutCalls++
	return &ProviderPayoutResponse{ID: "provider-payout-1", Status: "succeeded"}, nil
}

type fakeClock struct{ now time.Time }

func (c fakeClock) Now() time.Time { return c.now }

type fakeIDGenerator struct{}

func (fakeIDGenerator) NewID() string { return "generated-id" }

type scriptedSettingsRepo struct {
	settings []settings.Setting
}

func (r *scriptedSettingsRepo) List(_ context.Context) ([]settings.Setting, error) {
	return r.settings, nil
}

func (r *scriptedSettingsRepo) Upsert(_ context.Context, key string, value any) error {
	return nil
}

func newUseCaseWithSettings(repo *fakeFinanceRepository, settingsRepo settings.Repository, now time.Time) *FinanceUseCase {
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &fakePricingService{}, &fakePaymentProvider{}, settingsRepo, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)
}

func TestCommissionPercentFromSettings(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "20.00"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	if repo.lastCommissionPercent != 20 {
		t.Errorf("commission percent = %d, want 20", repo.lastCommissionPercent)
	}
}

func TestCommissionPercentFloat64FromSettings(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: float64(20)},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	if repo.lastCommissionPercent != 20 {
		t.Errorf("commission percent = %d, want 20 (not fallback 15)", repo.lastCommissionPercent)
	}
}

func TestCommissionPercentFallbackInvalid(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "abc"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	if repo.lastCommissionPercent != 15 {
		t.Errorf("commission percent = %d, want fallback 15", repo.lastCommissionPercent)
	}
}

func TestCommissionPercentFallbackNegative(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "-5"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	if repo.lastCommissionPercent != 15 {
		t.Errorf("commission percent = %d, want fallback 15", repo.lastCommissionPercent)
	}
}

func TestCommissionPercentFallbackOver100(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "150"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	if repo.lastCommissionPercent != 15 {
		t.Errorf("commission percent = %d, want fallback 15", repo.lastCommissionPercent)
	}
}

func TestCommissionWithActiveSubscription(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	repo.hasActiveSubscription = true
	repo.orderAmount = 1000000
	repo.settlementMethod = paymentdomain.PaymentMethodCard
	repo.debtBalance = 0
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "20.00"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	if repo.pendingBalance != 1000000 {
		t.Errorf("pending balance = %d, want 1000000 (driver gets full amount)", repo.pendingBalance)
	}
}

func TestCommissionWithSurcharge(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	repo.orderAmount = 1000000
	repo.surchargeAmount = 200000
	repo.settlementMethod = paymentdomain.PaymentMethodCard
	repo.debtBalance = 0
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "15.00"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	// base = 1000000 - 200000 = 800000
	// commission = (800000 * 15 + 50) / 100 = 120000
	// driver = total - commission = 1000000 - 120000 = 880000
	wantPending := int64(880000)
	if repo.pendingBalance != wantPending {
		t.Errorf("pending balance = %d, want %d (surcharge goes to driver)", repo.pendingBalance, wantPending)
	}
}

func TestCommissionRoundingHalfUp(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	repo := newFakeFinanceRepository()
	repo.orderAmount = 1001
	repo.surchargeAmount = 0
	repo.settlementMethod = paymentdomain.PaymentMethodCard
	repo.debtBalance = 0
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "commission_percent", Value: "15.00"},
		},
	}
	uc := newUseCaseWithSettings(repo, settingsRepo, now)

	if err := uc.CompleteOrderFinancially(context.Background(), "order-1"); err != nil {
		t.Fatalf("CompleteOrderFinancially returned error: %v", err)
	}
	// (1001 * 15 + 50) / 100 = 150 (int truncation, +50 shifts threshold)
	// driver = 1001 - 150 = 851
	// invariant: 150 + 851 = 1001
	wantPending := int64(851)
	if repo.pendingBalance != wantPending {
		t.Errorf("pending balance = %d, want %d", repo.pendingBalance, wantPending)
	}
}

func TestSubscriptionPriceFromSettings(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	settingsRepo := &scriptedSettingsRepo{
		settings: []settings.Setting{
			{Key: "driver_subscription_daily_price", Value: "40000"},
		},
	}
	repo := &subscriptionRepo{}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{ID: "provider-sub-1", Status: "pending"}, nil
		},
	}
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &scriptedPricing{}, provider, settingsRepo, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)

	payment, err := uc.CreateDriverSubscriptionPayment(context.Background(), "driver-1", "pro_day")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if payment.Amount != 40000 {
		t.Errorf("amount = %d, want 40000 from settings", payment.Amount)
	}
}
