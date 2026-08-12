package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
)

// Adversarial/edge coverage for ConfirmOrderPayment on top of
// finance_confirm_payment_test.go. Focus: idempotency of a repeated confirm,
// wrong-status confirms and foreign-user confirms.

// sharedConfirmState is written by the money tx fake (simulating the committed
// DB state) and read back by the order repo fake via GetByID, exactly mirroring
// the real "order row updated inside the completion tx" behaviour.
type sharedConfirmState struct {
	status           orderdomain.Status
	settlementCalls  int
	txOpened         int
	settlementKeys   []string
	statusUpdated    int
}

type sharedOrderRepo struct {
	*fakePaymentOrderRepo
	*sharedConfirmState
	template *orderdomain.Order
}

func (r *sharedOrderRepo) GetByID(_ context.Context, orderID string) (*orderdomain.Order, error) {
	if r.template == nil || r.template.ID != orderID {
		return nil, orderdomain.ErrOrderNotFound
	}
	o := *r.template
	o.Status = r.status
	return &o, nil
}

func (r *sharedOrderRepo) UpdateStatus(_ context.Context, _ string, _ orderdomain.Status, _ time.Time) error {
	r.statusUpdated++
	return nil
}

type sharedMoneyRepo struct {
	noopFinanceRepo
	*sharedConfirmState
	completeErr error
}

func (r *sharedMoneyRepo) CompleteOrderFinancially(_ context.Context, _, idempotencyKey string, _, _ int) error {
	if r.completeErr != nil {
		return r.completeErr
	}
	r.settlementCalls++
	r.settlementKeys = append(r.settlementKeys, idempotencyKey)
	return nil
}

func (r *sharedMoneyRepo) UpdateOrderStatus(_ context.Context, _ string, status string, _ time.Time) error {
	r.status = orderdomain.Status(status)
	return nil
}

func (r *sharedMoneyRepo) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	r.txOpened++
	return fn(r)
}

func newSharedConfirmUC(money *sharedMoneyRepo, order *sharedOrderRepo) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(money, order, &fakeDriverReleaseStore{}, &scriptedPricing{}, &scriptedProvider{}, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)
}

func sharedConfirmOrder(status orderdomain.Status, userID, method string) *orderdomain.Order {
	driverID := "driver-1"
	return &orderdomain.Order{
		ID:            "order-1",
		UserID:        userID,
		DriverID:      &driverID,
		Status:        status,
		PaymentMethod: method,
		PriceTotal:    1000000,
		UpdatedAt:     time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC),
	}
}

// TestConfirmOrderPaymentCash_DoubleConfirmNoDoubleSettlement proves that
// confirming the same cash order twice settles finances exactly once: the
// first call moves the order to completed (inside the tx), so the second call
// is rejected by the status guard before any money is touched.
func TestConfirmOrderPaymentCash_DoubleConfirmNoDoubleSettlement(t *testing.T) {
	state := &sharedConfirmState{status: orderdomain.StatusAwaitingPayment}
	money := &sharedMoneyRepo{sharedConfirmState: state}
	order := &sharedOrderRepo{
		sharedConfirmState: state,
		template:           sharedConfirmOrder(orderdomain.StatusAwaitingPayment, "client-1", "cash"),
	}
	uc := newSharedConfirmUC(money, order)

	if _, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1"); err != nil {
		t.Fatalf("first confirm failed: %v", err)
	}
	if state.settlementCalls != 1 {
		t.Fatalf("settlement calls after first = %d, want 1", state.settlementCalls)
	}
	if len(state.settlementKeys) != 1 || state.settlementKeys[0] != "complete_order:order-1" {
		t.Fatalf("settlement keys = %v, want [complete_order:order-1]", state.settlementKeys)
	}
	if state.status != orderdomain.StatusCompleted {
		t.Fatalf("order status after first confirm = %q, want %q", state.status, orderdomain.StatusCompleted)
	}

	if _, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1"); !errors.Is(err, orderdomain.ErrInvalidTransition) {
		t.Fatalf("second confirm err = %v, want ErrInvalidTransition (order already completed)", err)
	}
	if state.settlementCalls != 1 {
		t.Fatalf("settlement calls after duplicate confirm = %d, want 1 (no double settlement)", state.settlementCalls)
	}
	if state.txOpened != 1 {
		t.Fatalf("tx opened = %d, want 1 (duplicate must not open a completion tx)", state.txOpened)
	}
}

// TestConfirmOrderPayment_RejectsWrongStatus verifies a confirm in any status
// other than awaiting_payment is rejected without opening a transaction.
func TestConfirmOrderPayment_RejectsWrongStatus(t *testing.T) {
	statuses := []orderdomain.Status{
		orderdomain.StatusCreated,
		orderdomain.StatusAccepted,
		orderdomain.StatusInProgress,
		orderdomain.StatusCompleted,
		orderdomain.StatusCancelled,
	}
	for _, status := range statuses {
		t.Run(string(status), func(t *testing.T) {
			state := &sharedConfirmState{status: status}
			money := &sharedMoneyRepo{sharedConfirmState: state}
			order := &sharedOrderRepo{
				sharedConfirmState: state,
				template:           sharedConfirmOrder(status, "client-1", "cash"),
			}
			uc := newSharedConfirmUC(money, order)

			_, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
			if !errors.Is(err, orderdomain.ErrInvalidTransition) {
				t.Fatalf("err = %v, want ErrInvalidTransition", err)
			}
			if state.txOpened != 0 {
				t.Fatalf("tx opened = %d, want 0 for wrong status", state.txOpened)
			}
			if state.settlementCalls != 0 {
				t.Fatalf("settlement calls = %d, want 0 for wrong status", state.settlementCalls)
			}
		})
	}
}

// TestConfirmOrderPayment_RejectsForeignUser verifies a user who does not own
// the order cannot confirm payment for it.
func TestConfirmOrderPayment_RejectsForeignUser(t *testing.T) {
	state := &sharedConfirmState{status: orderdomain.StatusAwaitingPayment}
	money := &sharedMoneyRepo{sharedConfirmState: state}
	order := &sharedOrderRepo{
		sharedConfirmState: state,
		template:           sharedConfirmOrder(orderdomain.StatusAwaitingPayment, "client-1", "cash"),
	}
	uc := newSharedConfirmUC(money, order)

	_, err := uc.ConfirmOrderPayment(context.Background(), "client-hacker", "order-1")
	if !errors.Is(err, ErrOrderNotOwned) {
		t.Fatalf("err = %v, want ErrOrderNotOwned", err)
	}
	if state.txOpened != 0 {
		t.Fatalf("tx opened = %d, want 0 for foreign user", state.txOpened)
	}
	if state.settlementCalls != 0 {
		t.Fatalf("settlement calls = %d, want 0 for foreign user", state.settlementCalls)
	}
}

// TestConfirmOrderPaymentCash_SettlementAndCompletedAtomically asserts the
// ok path: settlement and the completed-status write happen together inside a
// single WithWebhookTx and the completed order reflects the settled money.
func TestConfirmOrderPaymentCash_SettlementAndCompletedAtomically(t *testing.T) {
	state := &sharedConfirmState{status: orderdomain.StatusAwaitingPayment}
	money := &sharedMoneyRepo{sharedConfirmState: state}
	order := &sharedOrderRepo{
		sharedConfirmState: state,
		template:           sharedConfirmOrder(orderdomain.StatusAwaitingPayment, "client-1", "cash"),
	}
	uc := newSharedConfirmUC(money, order)

	payment, err := uc.ConfirmOrderPayment(context.Background(), "client-1", "order-1")
	if err != nil {
		t.Fatalf("ConfirmOrderPayment returned error: %v", err)
	}
	if payment != nil {
		t.Fatalf("cash confirm payment = %v, want nil", payment)
	}
	if state.txOpened != 1 {
		t.Fatalf("tx opened = %d, want 1 (money + status must be one tx)", state.txOpened)
	}
	if state.settlementCalls != 1 {
		t.Fatalf("settlement calls = %d, want 1", state.settlementCalls)
	}
	if state.status != orderdomain.StatusCompleted {
		t.Fatalf("order status = %q, want %q", state.status, orderdomain.StatusCompleted)
	}
	// The persisted order must read back as completed with the server price.
	persisted, err := order.GetByID(context.Background(), "order-1")
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if persisted.Status != orderdomain.StatusCompleted {
		t.Fatalf("read-back status = %q, want completed", persisted.Status)
	}
}