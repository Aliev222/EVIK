package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

type refundRepo struct {
	noopFinanceRepo
	createRefundCalls int
	createRefundArg   *paymentdomain.Refund
	createRefundErr   error
}

func (r *refundRepo) CreateRefund(_ context.Context, refund *paymentdomain.Refund) (*paymentdomain.Refund, error) {
	r.createRefundCalls++
	r.createRefundArg = refund
	if r.createRefundErr != nil {
		return nil, r.createRefundErr
	}
	return refund, nil
}

func newRefundUC(repo paymentdomain.Repository) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, &scriptedProvider{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, true)
}

func TestCreateRefundRejectsNonPositiveAmount(t *testing.T) {
	tests := []int64{0, -1, -100000}
	for _, amount := range tests {
		t.Run("amount="+intToStr(int(amount)), func(t *testing.T) {
			repo := &refundRepo{}
			uc := newRefundUC(repo)
			_, err := uc.CreateRefund(context.Background(), "payment-1", amount, "client_canceled")
			if !errors.Is(err, paymentdomain.ErrInvalidAmount) {
				t.Fatalf("err = %v, want ErrInvalidAmount", err)
			}
			if repo.createRefundCalls != 0 {
				t.Errorf("repo should not be called for invalid amount, calls = %d", repo.createRefundCalls)
			}
		})
	}
}

func TestCreateRefundHappyPath(t *testing.T) {
	repo := &refundRepo{}
	uc := newRefundUC(repo)

	refund, err := uc.CreateRefund(context.Background(), "payment-1", 250000, "order_disputed")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if refund == nil {
		t.Fatal("refund is nil on success")
	}
	if refund.PaymentID != "payment-1" {
		t.Errorf("PaymentID = %q, want payment-1", refund.PaymentID)
	}
	if refund.Amount != 250000 {
		t.Errorf("Amount = %d, want 250000", refund.Amount)
	}
	if refund.Reason != "order_disputed" {
		t.Errorf("Reason = %q, want order_disputed", refund.Reason)
	}
	if refund.Status != paymentdomain.RefundStatusCreated {
		t.Errorf("Status = %q, want created", refund.Status)
	}
	if refund.Currency != paymentdomain.CurrencyRUB {
		t.Errorf("Currency = %q, want RUB", refund.Currency)
	}
}

func TestCreateRefundIdempotencyKeyFormat(t *testing.T) {
	repo := &refundRepo{}
	uc := newRefundUC(repo)

	_, err := uc.CreateRefund(context.Background(), "pay-X", 99000, "duplicate")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.createRefundArg == nil {
		t.Fatal("repo never received refund argument")
	}
	want := "refund:pay-X:99000:duplicate"
	if repo.createRefundArg.IdempotencyKey != want {
		t.Errorf("IdempotencyKey = %q, want %q", repo.createRefundArg.IdempotencyKey, want)
	}
}

func TestCreateRefundDuplicateBlockedByIdempotencyKey(t *testing.T) {
	repo := &refundRepo{}
	uc := newRefundUC(repo)

	r1, err := uc.CreateRefund(context.Background(), "payment-1", 100000, "client_canceled")
	if err != nil {
		t.Fatalf("first refund err = %v", err)
	}
	r2, err := uc.CreateRefund(context.Background(), "payment-1", 100000, "client_canceled")
	if err != nil {
		t.Fatalf("second refund err = %v", err)
	}

	if r1.IdempotencyKey != r2.IdempotencyKey {
		t.Errorf("idempotency keys differ for identical refund attempts: %q vs %q", r1.IdempotencyKey, r2.IdempotencyKey)
	}
}

func TestCreateRefundRepoErrorPropagates(t *testing.T) {
	wantErr := errors.New("constraint violation")
	repo := &refundRepo{createRefundErr: wantErr}
	uc := newRefundUC(repo)

	_, err := uc.CreateRefund(context.Background(), "payment-1", 100000, "reason")
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}
