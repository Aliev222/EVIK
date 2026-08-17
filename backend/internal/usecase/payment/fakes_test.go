package payment

import (
	"context"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
	pricingdomain "evik/backend/internal/domain/pricing"
)

// fakeDriverReleaseStore is a no-op stub for the DriverReleaseStore interface.
type fakeDriverReleaseStore struct{}

func (s *fakeDriverReleaseStore) ReleaseOrder(_ context.Context, _ string, _ string, _ time.Time) error {
	return nil
}

// noopFinanceRepo provides a baseline no-op implementation of every method
// of paymentdomain.Repository. Tests embed it in their own fake type and
// override only the methods they exercise. This avoids panics from missing
// methods and keeps each test file focused.
type noopFinanceRepo struct{}

func (noopFinanceRepo) ListMethods(context.Context, string) ([]paymentdomain.PaymentMethod, error) {
	return nil, nil
}
func (noopFinanceRepo) AddMethod(context.Context, paymentdomain.PaymentMethod) error { return nil }
func (noopFinanceRepo) CreatePendingPaymentMethod(context.Context, *paymentdomain.Payment, paymentdomain.PaymentMethod) (*paymentdomain.AddCardInit, error) {
	return nil, nil
}
func (noopFinanceRepo) SetDefaultMethod(context.Context, string, string) (*paymentdomain.PaymentMethod, error) {
	return nil, nil
}
func (noopFinanceRepo) DeleteMethod(context.Context, string, string) error { return nil }
func (noopFinanceRepo) ListClientPayments(context.Context, string, int, int) ([]paymentdomain.PaymentTransaction, error) {
	return nil, nil
}
func (noopFinanceRepo) CreateOrderPayment(_ context.Context, p *paymentdomain.Payment) (*paymentdomain.Payment, error) {
	return p, nil
}
func (noopFinanceRepo) AttachProviderPayment(context.Context, string, string, string, *string, *time.Time) (*paymentdomain.Payment, error) {
	return nil, nil
}
func (noopFinanceRepo) AttachPaymentMethodProvider(context.Context, string, string) error { return nil }
func (noopFinanceRepo) CreateSubscriptionPayment(_ context.Context, p *paymentdomain.Payment, _ *paymentdomain.Subscription) (*paymentdomain.Payment, error) {
	return p, nil
}
func (noopFinanceRepo) GetPayment(context.Context, string) (*paymentdomain.Payment, error) {
	return nil, nil
}
func (noopFinanceRepo) GetPaymentByOrderID(context.Context, string) (*paymentdomain.Payment, error) {
	return nil, nil
}
func (noopFinanceRepo) UpdatePaymentFromProvider(context.Context, string, string, bool) (*paymentdomain.Payment, error) {
	return &paymentdomain.Payment{Purpose: paymentdomain.PaymentPurposeOrder}, nil
}
func (noopFinanceRepo) StoreWebhook(context.Context, string, string, string, []byte) (bool, error) {
	return true, nil
}
func (noopFinanceRepo) MarkWebhookProcessed(context.Context, string) error { return nil }
func (noopFinanceRepo) CompleteOrderFinancially(context.Context, string, string, int, int) error {
	return nil
}
func (noopFinanceRepo) UpdateOrderStatus(context.Context, string, string, time.Time) error {
	return nil
}
func (noopFinanceRepo) ListReleasablePendingTransactions(context.Context, int) ([]paymentdomain.WalletTransaction, error) {
	return nil, nil
}
func (noopFinanceRepo) MarkTransactionReleased(context.Context, string) error { return nil }
func (noopFinanceRepo) GetDriverWallet(context.Context, string) (*paymentdomain.DriverWallet, error) {
	return nil, nil
}
func (noopFinanceRepo) GetDriverEarnings(context.Context, string, time.Time, time.Time, time.Time) (paymentdomain.DriverEarnings, error) {
	return paymentdomain.DriverEarnings{}, nil
}
func (noopFinanceRepo) ListWalletTransactions(context.Context, string, int) ([]paymentdomain.WalletTransaction, error) {
	return nil, nil
}
func (noopFinanceRepo) ListDebtTransactions(context.Context, string, int) ([]paymentdomain.DriverDebtTransaction, error) {
	return nil, nil
}
func (noopFinanceRepo) ListPayouts(context.Context, string, int) ([]paymentdomain.Payout, error) {
	return nil, nil
}
func (noopFinanceRepo) ListPayoutMethods(context.Context, string) ([]paymentdomain.DriverPayoutMethod, error) {
	return nil, nil
}
func (noopFinanceRepo) AddPayoutMethod(context.Context, paymentdomain.DriverPayoutMethod) error {
	return nil
}
func (noopFinanceRepo) CreatePayout(_ context.Context, p *paymentdomain.Payout, idempotencyKey string) (*paymentdomain.Payout, error) {
	p.IdempotencyKey = idempotencyKey
	return p, nil
}
func (noopFinanceRepo) MarkPayoutPaid(context.Context, string, string, string) error { return nil }
func (noopFinanceRepo) MarkPayoutFailed(context.Context, string, string) error       { return nil }
func (noopFinanceRepo) GetActiveDriverSubscription(context.Context, string) (*paymentdomain.Subscription, error) {
	return nil, nil
}
func (noopFinanceRepo) GetLatestDriverSubscription(context.Context, string) (*paymentdomain.Subscription, error) {
	return nil, nil
}
func (noopFinanceRepo) ActivateSubscriptionByPayment(context.Context, string) error { return nil }
func (noopFinanceRepo) ActivatePaymentMethodFromProvider(context.Context, string, string, string, string, int, int, string) error {
	return nil
}
func (noopFinanceRepo) CheckProcessed(context.Context, string, string, string, []byte) (bool, error) {
	return false, nil
}
func (noopFinanceRepo) MarkProcessed(context.Context, string) error { return nil }
func (noopFinanceRepo) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	return fn(noopFinanceRepo{})
}
func (noopFinanceRepo) ExportFinanceReport(context.Context, string) ([][]string, error) {
	return nil, nil
}
func (noopFinanceRepo) GetPayout(context.Context, string) (*paymentdomain.Payout, error) {
	return nil, nil
}
func (noopFinanceRepo) ApprovePayout(context.Context, string, string, string, time.Time) (*paymentdomain.Payout, error) {
	return nil, nil
}
func (noopFinanceRepo) RejectPayout(context.Context, string, string, string, time.Time) (*paymentdomain.Payout, error) {
	return nil, nil
}
func (noopFinanceRepo) ListAdminRefunds(context.Context, paymentdomain.AdminRefundFilter) ([]paymentdomain.Refund, int64, error) {
	return nil, 0, nil
}
func (noopFinanceRepo) ListWalletTransactionsByOrder(context.Context, string) ([]paymentdomain.WalletTransaction, error) {
	return nil, nil
}
func (noopFinanceRepo) ListStuckPayouts(context.Context, time.Duration) ([]paymentdomain.Payout, error) {
	return nil, nil
}

// Compile-time check: if a new method is added to paymentdomain.Repository,
// the test suite will fail to compile here, flagging that the no-op base
// needs to be extended.
var _ paymentdomain.Repository = noopFinanceRepo{}

// scriptedProvider is a PaymentProvider driven by per-test function fields.
// If a field is nil, a sensible default response is returned. Call args
// are recorded for assertions.
type scriptedProvider struct {
	createPaymentFn func(ctx context.Context, req ProviderPaymentRequest) (*ProviderPaymentResponse, error)
	createPayoutFn  func(ctx context.Context, req ProviderPayoutRequest) (*ProviderPayoutResponse, error)
	getPaymentFn    func(ctx context.Context, id string) (*ProviderPaymentResponse, error)

	paymentCalls  []ProviderPaymentRequest
	payoutCalls   []ProviderPayoutRequest
	getPaymentIDs []string
}

func (p *scriptedProvider) CreatePayment(ctx context.Context, req ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
	p.paymentCalls = append(p.paymentCalls, req)
	if p.createPaymentFn != nil {
		return p.createPaymentFn(ctx, req)
	}
	return &ProviderPaymentResponse{ID: "provider-payment-default", Status: "pending"}, nil
}

func (p *scriptedProvider) GetPayment(ctx context.Context, id string) (*ProviderPaymentResponse, error) {
	p.getPaymentIDs = append(p.getPaymentIDs, id)
	if p.getPaymentFn != nil {
		return p.getPaymentFn(ctx, id)
	}
	return &ProviderPaymentResponse{ID: id, Status: "succeeded", Paid: true}, nil
}

func (p *scriptedProvider) CreatePayout(ctx context.Context, req ProviderPayoutRequest) (*ProviderPayoutResponse, error) {
	p.payoutCalls = append(p.payoutCalls, req)
	if p.createPayoutFn != nil {
		return p.createPayoutFn(ctx, req)
	}
	return &ProviderPayoutResponse{ID: "provider-payout-default", Status: "succeeded"}, nil
}

// scriptedPricing returns a fixed total price or error.
type scriptedPricing struct {
	totalPrice int64
	err        error
}

func (s *scriptedPricing) CalculatePrice(_ context.Context, input pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error) {
	if s.err != nil {
		return nil, s.err
	}
	return &pricingdomain.PriceCalculation{
		OrderID:    input.OrderID,
		TotalPrice: s.totalPrice,
	}, nil
}

// incrementingIDGen returns sequential ids "id-1", "id-2", ... — useful when
// a single use case generates multiple IDs (payment + subscription) and the
// test wants to distinguish them.
type incrementingIDGen struct{ n int }

func (g *incrementingIDGen) NewID() string {
	g.n++
	return "id-" + intToStr(g.n)
}

func intToStr(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
