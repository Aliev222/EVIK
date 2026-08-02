package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
)

// confirmRepo records the tx-scoped completion operations so tests can assert
// that money settlement and the order status update run inside a single
// WithWebhookTx invocation. Its WithWebhookTx simulates the real transaction:
// when the callback returns an error, the writes performed inside it are
// discarded (all-or-nothing), mirroring the rollback of the postgres tx.
type confirmRepo struct {
	noopFinanceRepo
	txOpenCalls      int
	completeCalls    int
	statusUpdates    []string
	failCompleteTx   bool
	failStatusUpdate bool
}

func (r *confirmRepo) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	r.txOpenCalls++
	if err := fn(r); err != nil {
		r.completeCalls = 0
		r.statusUpdates = nil
		return err
	}
	return nil
}

func (r *confirmRepo) CompleteOrderFinancially(_ context.Context, _, _ string, _, _ int) error {
	r.completeCalls++
	if r.failCompleteTx {
		return errors.New("financial settlement failed")
	}
	return nil
}

func (r *confirmRepo) UpdateOrderStatus(_ context.Context, _ string, status string, _ time.Time) error {
	r.statusUpdates = append(r.statusUpdates, status)
	if r.failStatusUpdate {
		return errors.New("order status update failed")
	}
	return nil
}

// confirmOrderRepo returns a fixed awaiting_payment order and counts any
// UpdateStatus calls made through the plain order repository — those must be
// zero after the fix, since the status write goes through the completion tx.
type confirmOrderRepo struct {
	*fakePaymentOrderRepo
	order             *orderdomain.Order
	updateStatusCalls int
}

func (r *confirmOrderRepo) GetByID(context.Context, string) (*orderdomain.Order, error) {
	return r.order, nil
}

func (r *confirmOrderRepo) UpdateStatus(_ context.Context, _ string, _ orderdomain.Status, _ time.Time) error {
	r.updateStatusCalls++
	return nil
}

func newConfirmOrder(paymentMethod string) *orderdomain.Order {
	driverID := "driver-1"
	return &orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusAwaitingPayment,
		PaymentMethod: paymentMethod,
		PriceTotal:    1000000,
		UpdatedAt:     time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC),
	}
}

func newConfirmUC(repo paymentdomain.Repository, orderRepo *confirmOrderRepo, provider PaymentProvider) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, orderRepo, &fakeDriverReleaseStore{}, &fakePricingService{}, provider, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)
}

// TestConfirmOrderPaymentCash_OneTransaction verifies the cash confirm path:
// financial settlement and the completed-status write happen inside a single
// WithWebhookTx, and the old non-transactional orderRepo.UpdateStatus is no
// longer used.
func TestConfirmOrderPaymentCash_OneTransaction(t *testing.T) {
	repo := &confirmRepo{}
	orderRepo := &confirmOrderRepo{order: newConfirmOrder("cash")}
	uc := newConfirmUC(repo, orderRepo, &fakePaymentProvider{})

	payment, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
	if err != nil {
		t.Fatalf("ConfirmOrderPayment returned error: %v", err)
	}
	if payment != nil {
		t.Fatalf("cash confirm payment = %v, want nil", payment)
	}
	if repo.txOpenCalls != 1 {
		t.Fatalf("WithWebhookTx calls = %d, want 1 (money+status must be one tx)", repo.txOpenCalls)
	}
	if repo.completeCalls != 1 {
		t.Fatalf("CompleteOrderFinancially (tx) calls = %d, want 1", repo.completeCalls)
	}
	if len(repo.statusUpdates) != 1 || repo.statusUpdates[0] != string(orderdomain.StatusCompleted) {
		t.Fatalf("tx status updates = %+v, want [completed]", repo.statusUpdates)
	}
	if orderRepo.updateStatusCalls != 0 {
		t.Fatalf("orderRepo.UpdateStatus calls = %d, want 0 (must go through the tx)", orderRepo.updateStatusCalls)
	}
}

// TestConfirmOrderPaymentCash_AllOrNothing verifies that when the status write
// fails inside the completion tx, the money settlement that happened in the
// same tx is discarded — nothing is committed.
func TestConfirmOrderPaymentCash_AllOrNothing(t *testing.T) {
	repo := &confirmRepo{failStatusUpdate: true}
	orderRepo := &confirmOrderRepo{order: newConfirmOrder("cash")}
	uc := newConfirmUC(repo, orderRepo, &fakePaymentProvider{})

	payment, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
	if err == nil {
		t.Fatal("expected error when order status update fails, got nil")
	}
	if payment != nil {
		t.Fatalf("payment = %v, want nil on failure", payment)
	}
	if repo.txOpenCalls != 1 {
		t.Fatalf("WithWebhookTx calls = %d, want 1", repo.txOpenCalls)
	}
	// Rolled back: the money settlement recorded inside the tx is discarded.
	if repo.completeCalls != 0 {
		t.Fatalf("CompleteOrderFinancially side effects = %d, want 0 (rolled back)", repo.completeCalls)
	}
	if len(repo.statusUpdates) != 0 {
		t.Fatalf("status updates = %+v, want none (rolled back)", repo.statusUpdates)
	}
}

// TestConfirmOrderPaymentCash_SettlementFailure verifies a settlement failure
// aborts the whole completion without touching the order status.
func TestConfirmOrderPaymentCash_SettlementFailure(t *testing.T) {
	repo := &confirmRepo{failCompleteTx: true}
	orderRepo := &confirmOrderRepo{order: newConfirmOrder("cash")}
	uc := newConfirmUC(repo, orderRepo, &fakePaymentProvider{})

	payment, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
	if err == nil {
		t.Fatal("expected error when financial settlement fails, got nil")
	}
	if payment != nil {
		t.Fatalf("payment = %v, want nil on failure", payment)
	}
	if len(repo.statusUpdates) != 0 {
		t.Fatalf("status updates = %+v, want none when settlement fails", repo.statusUpdates)
	}
	if orderRepo.updateStatusCalls != 0 {
		t.Fatalf("orderRepo.UpdateStatus calls = %d, want 0", orderRepo.updateStatusCalls)
	}
}

// TestConfirmOrderPaymentCardSucceeded_OneTransaction verifies the card path
// when the payment is paid at creation: the same single-tx completion as cash.
func TestConfirmOrderPaymentCardSucceeded_OneTransaction(t *testing.T) {
	repo := &confirmRepo{}
	orderRepo := &confirmOrderRepo{order: newConfirmOrder("card")}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{ID: "pp-1", Status: "succeeded", Paid: true}, nil
		},
	}
	uc := newConfirmUC(repo, orderRepo, provider)

	payment, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
	if err != nil {
		t.Fatalf("ConfirmOrderPayment returned error: %v", err)
	}
	if payment == nil || payment.Status != paymentdomain.PaymentStatusSucceeded {
		t.Fatalf("payment = %v, want succeeded payment", payment)
	}
	if repo.txOpenCalls != 1 {
		t.Fatalf("WithWebhookTx calls = %d, want 1", repo.txOpenCalls)
	}
	if repo.completeCalls != 1 {
		t.Fatalf("CompleteOrderFinancially (tx) calls = %d, want 1", repo.completeCalls)
	}
	if len(repo.statusUpdates) != 1 || repo.statusUpdates[0] != string(orderdomain.StatusCompleted) {
		t.Fatalf("tx status updates = %+v, want [completed]", repo.statusUpdates)
	}
	if orderRepo.updateStatusCalls != 0 {
		t.Fatalf("orderRepo.UpdateStatus calls = %d, want 0", orderRepo.updateStatusCalls)
	}
}

// TestConfirmOrderPaymentCardPending_NoCompletionTx verifies that a card
// payment that is not paid at creation returns a confirmation URL without
// settling anything or opening a completion tx.
func TestConfirmOrderPaymentCardPending_NoCompletionTx(t *testing.T) {
	repo := &confirmRepo{}
	orderRepo := &confirmOrderRepo{order: newConfirmOrder("card")}
	uc := newConfirmUC(repo, orderRepo, &fakePaymentProvider{})

	payment, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
	if err != nil {
		t.Fatalf("ConfirmOrderPayment returned error: %v", err)
	}
	if payment == nil || payment.Status == paymentdomain.PaymentStatusSucceeded {
		t.Fatalf("payment = %v, want pending payment", payment)
	}
	if repo.txOpenCalls != 0 {
		t.Fatalf("WithWebhookTx calls = %d, want 0 (no completion for pending card)", repo.txOpenCalls)
	}
	if repo.completeCalls != 0 {
		t.Fatalf("CompleteOrderFinancially calls = %d, want 0", repo.completeCalls)
	}
}
