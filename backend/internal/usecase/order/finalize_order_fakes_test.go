package order

import (
	"context"
	"errors"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
)

// fakePaymentTxRunner simulates the PaymentRepository.WithWebhookTx used by the
// cash auto-completion path. Its WithWebhookTx behaves like a database
// transaction: when the callback returns an error, the settlement/status
// writes recorded inside it are discarded (all-or-nothing), mirroring the
// rollback of the postgres tx. On success the terminal status is committed back
// into the fake order repository.
type fakePaymentTxRunner struct {
	orderRepo            *fakeOrderRepository
	txOpenCalls          int
	completeCalls        int
	lastIdempotencyKey   string
	lastCommissionPercent int
	lastHoldSeconds      int
	statusUpdates        []string
	pendingStatus        string
	failComplete         bool
	failStatusUpdate     bool
}

type fakeWebhookTxOps struct{ parent *fakePaymentTxRunner }

func (w *fakeWebhookTxOps) CheckProcessed(context.Context, string, string, string, []byte) (bool, error) {
	return false, nil
}
func (w *fakeWebhookTxOps) UpdatePaymentFromProvider(context.Context, string, string, bool) (*paymentdomain.Payment, error) {
	return nil, nil
}
func (w *fakeWebhookTxOps) ActivateSubscriptionByPayment(context.Context, string) error {
	return nil
}
func (w *fakeWebhookTxOps) ActivatePaymentMethodFromProvider(context.Context, string, string, string, string, int, int, string) error {
	return nil
}
func (w *fakeWebhookTxOps) CompleteOrderFinancially(_ context.Context, _, idempotencyKey string, holdSeconds, commissionPercent int) error {
	p := w.parent
	p.completeCalls++
	p.lastIdempotencyKey = idempotencyKey
	p.lastHoldSeconds = holdSeconds
	p.lastCommissionPercent = commissionPercent
	if p.failComplete {
		return errors.New("financial settlement failed")
	}
	return nil
}
func (w *fakeWebhookTxOps) UpdateOrderStatus(_ context.Context, _, status string, _ time.Time) error {
	p := w.parent
	p.statusUpdates = append(p.statusUpdates, status)
	p.pendingStatus = status
	if p.failStatusUpdate {
		return errors.New("order status update failed")
	}
	return nil
}
func (w *fakeWebhookTxOps) MarkProcessed(context.Context, string) error { return nil }

func (r *fakePaymentTxRunner) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	r.txOpenCalls++
	r.pendingStatus = ""
	if err := fn(&fakeWebhookTxOps{parent: r}); err != nil {
		r.completeCalls = 0
		r.statusUpdates = nil
		r.pendingStatus = ""
		return err
	}
	r.commitStatus(r.pendingStatus)
	return nil
}

func (r *fakePaymentTxRunner) commitStatus(status string) {
	if r.orderRepo == nil || status == "" || r.orderRepo.order == nil {
		return
	}
	r.orderRepo.order.Status = orderdomain.Status(status)
	if r.orderRepo.orders != nil {
		if o, ok := r.orderRepo.orders[r.orderRepo.order.ID]; ok {
			o.Status = orderdomain.Status(status)
		}
	}
}

// fakeCommissionProvider is a fixed CommissionPercentProvider for finalize
// tests.
type fakeCommissionProvider struct{ percent int }

func (p fakeCommissionProvider) CommissionPercent(context.Context) int {
	return p.percent
}