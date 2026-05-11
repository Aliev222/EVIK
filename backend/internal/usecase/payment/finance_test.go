package payment

import (
	"context"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	pricingdomain "evik/backend/internal/domain/pricing"
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
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakePricingService{}, provider, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, "")

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

	if err := uc.HandleYooKassaWebhook(context.Background(), payload, ""); err != nil {
		t.Fatalf("first webhook returned error: %v", err)
	}
	if err := uc.HandleYooKassaWebhook(context.Background(), payload, ""); err != nil {
		t.Fatalf("duplicate webhook returned error: %v", err)
	}

	if repo.storeWebhookCalls != 2 {
		t.Fatalf("store webhook calls = %d, want 2", repo.storeWebhookCalls)
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
	if err := repo.CompleteOrderFinancially(context.Background(), "cash-order", "complete_order:cash-order", 600); err != nil {
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
	if err := repo.CompleteOrderFinancially(context.Background(), "card-order", "complete_order:card-order", 600); err != nil {
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

func newTestFinanceUseCase(repo *fakeFinanceRepository, now time.Time) *FinanceUseCase {
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakePricingService{}, &fakePaymentProvider{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, "")
}

type fakeFinanceRepository struct {
	paymentdomain.Repository
	webhooks                  map[string]bool
	settlementMethod          paymentdomain.PaymentMethodType
	orderAmount               int64
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

func (r *fakeFinanceRepository) UpdatePaymentFromProvider(_ context.Context, providerPaymentID, status string, paid bool) (*paymentdomain.Payment, error) {
	r.updatePaymentCalls++
	return &paymentdomain.Payment{ID: "payment-1", Purpose: paymentdomain.PaymentPurposeOrder, Status: paymentdomain.PaymentStatus(status)}, nil
}

func (r *fakeFinanceRepository) CompleteOrderFinancially(_ context.Context, orderID, idempotencyKey string, holdSeconds int) error {
	r.completeOrderCalls++
	r.completeIdempotencyKey = idempotencyKey
	total := r.orderAmount
	commission := total * 15 / 100
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

func (r *fakePaymentOrderRepo) Create(context.Context, *orderdomain.Order) error { return nil }
func (r *fakePaymentOrderRepo) Update(context.Context, *orderdomain.Order) error { return nil }
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

func (p *fakePaymentProvider) CreatePayout(_ context.Context, req ProviderPayoutRequest) (*ProviderPayoutResponse, error) {
	p.payoutCalls++
	return &ProviderPayoutResponse{ID: "provider-payout-1", Status: "succeeded"}, nil
}

type fakeClock struct{ now time.Time }

func (c fakeClock) Now() time.Time { return c.now }

type fakeIDGenerator struct{}

func (fakeIDGenerator) NewID() string { return "generated-id" }
