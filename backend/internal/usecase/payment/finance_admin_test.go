package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

// TestApprovePayoutHappyPath verifies ApprovePayout fetches the payout via
// GetPayout, then asks the repository to approve it with the moderator id and
// returns the updated payout to the caller.
func TestApprovePayoutHappyPath(t *testing.T) {
	now := time.Date(2026, 5, 11, 10, 0, 0, 0, time.UTC)
	repo := newFakeAdminPaymentRepo()
	repo.payouts["payout-1"] = paymentdomain.Payout{
		ID: "payout-1", DriverID: "driver-1", WalletID: "wallet-1",
		Amount: 100000, Currency: "RUB",
		Status: paymentdomain.PayoutStatusCreated,
	}
	uc := newAdminFinanceUseCase(repo, now)

	updated, err := uc.ApprovePayout(context.Background(), "payout-1", "admin-1")
	if err != nil {
		t.Fatalf("ApprovePayout returned error: %v", err)
	}
	if updated.Status != paymentdomain.PayoutStatusPaid {
		t.Fatalf("status = %q, want paid", updated.Status)
	}
	if repo.approveCalls != 1 {
		t.Fatalf("approve calls = %d, want 1", repo.approveCalls)
	}
	if repo.lastModerator != "admin-1" {
		t.Fatalf("moderator = %q, want admin-1", repo.lastModerator)
	}
}

// TestApprovePayoutIdempotentForAlreadyPaid skips the repo call when the
// payout is already paid, returning the existing record unchanged.
func TestApprovePayoutIdempotentForAlreadyPaid(t *testing.T) {
	now := time.Date(2026, 5, 11, 10, 0, 0, 0, time.UTC)
	repo := newFakeAdminPaymentRepo()
	repo.payouts["payout-paid"] = paymentdomain.Payout{
		ID:     "payout-paid",
		Status: paymentdomain.PayoutStatusPaid,
	}
	uc := newAdminFinanceUseCase(repo, now)

	updated, err := uc.ApprovePayout(context.Background(), "payout-paid", "admin-1")
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if updated.Status != paymentdomain.PayoutStatusPaid {
		t.Fatalf("status = %q, want paid", updated.Status)
	}
	if repo.approveCalls != 0 {
		t.Fatalf("approve calls = %d, want 0 (idempotent)", repo.approveCalls)
	}
}

// TestApprovePayoutNotFound returns the domain error for missing payouts.
func TestApprovePayoutNotFound(t *testing.T) {
	uc := newAdminFinanceUseCase(newFakeAdminPaymentRepo(), time.Now())
	_, err := uc.ApprovePayout(context.Background(), "no-such", "admin-1")
	if !errors.Is(err, paymentdomain.ErrPayoutNotFound) {
		t.Fatalf("err = %v, want ErrPayoutNotFound", err)
	}
}

// TestRejectPayoutHappyPath asserts that RejectPayout validates the reason
// and forwards the call to the repository.
func TestRejectPayoutHappyPath(t *testing.T) {
	now := time.Date(2026, 5, 11, 11, 0, 0, 0, time.UTC)
	repo := newFakeAdminPaymentRepo()
	repo.payouts["payout-2"] = paymentdomain.Payout{
		ID: "payout-2", DriverID: "driver-2", WalletID: "wallet-2",
		Amount: 50000, Status: paymentdomain.PayoutStatusCreated,
	}
	uc := newAdminFinanceUseCase(repo, now)

	updated, err := uc.RejectPayout(context.Background(), "payout-2", "admin-1", "wrong details on the recipient card")
	if err != nil {
		t.Fatalf("RejectPayout returned error: %v", err)
	}
	if updated.Status != paymentdomain.PayoutStatusCancelled {
		t.Fatalf("status = %q, want cancelled", updated.Status)
	}
	if repo.lastRejectReason != "wrong details on the recipient card" {
		t.Fatalf("reason = %q", repo.lastRejectReason)
	}
}

// TestRejectPayoutEmptyReason refuses to call the repository without a reason.
func TestRejectPayoutEmptyReason(t *testing.T) {
	uc := newAdminFinanceUseCase(newFakeAdminPaymentRepo(), time.Now())
	_, err := uc.RejectPayout(context.Background(), "payout-x", "admin-1", "   ")
	if !errors.Is(err, paymentdomain.ErrValidationFailed) {
		t.Fatalf("err = %v, want ErrValidationFailed", err)
	}
}

// TestListAdminRefundsPassesFiltersThrough verifies the use case is a thin
// pass-through to the repository contract.
func TestListAdminRefundsPassesFiltersThrough(t *testing.T) {
	repo := newFakeAdminPaymentRepo()
	from := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 5, 11, 23, 59, 0, 0, time.UTC)
	repo.refunds = []paymentdomain.Refund{
		{ID: "rf-1", PaymentID: "pay-1", Amount: 30000, Status: paymentdomain.RefundStatusCreated},
		{ID: "rf-2", PaymentID: "pay-2", Amount: 50000, Status: paymentdomain.RefundStatusSucceeded},
	}
	uc := newAdminFinanceUseCase(repo, time.Now())

	got, total, err := uc.ListAdminRefunds(context.Background(), paymentdomain.AdminRefundFilter{
		Status: "succeeded", From: &from, To: &to, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListAdminRefunds returned error: %v", err)
	}
	if total != int64(len(repo.refunds)) {
		t.Fatalf("total = %d, want %d", total, len(repo.refunds))
	}
	if len(got) != len(repo.refunds) {
		t.Fatalf("items = %d, want %d", len(got), len(repo.refunds))
	}
	if repo.lastRefundFilter.Status != "succeeded" {
		t.Fatalf("status filter = %q, want succeeded", repo.lastRefundFilter.Status)
	}
	if repo.lastRefundFilter.From == nil || !repo.lastRefundFilter.From.Equal(from) {
		t.Fatalf("from filter not propagated: %+v", repo.lastRefundFilter.From)
	}
}

// --- fake repo with only the methods used by the admin use case methods ---

type fakeAdminPaymentRepo struct {
	paymentdomain.Repository

	payouts          map[string]paymentdomain.Payout
	approveCalls     int
	rejectCalls      int
	lastModerator    string
	lastRejectReason string
	refunds          []paymentdomain.Refund
	lastRefundFilter paymentdomain.AdminRefundFilter
}

func newFakeAdminPaymentRepo() *fakeAdminPaymentRepo {
	return &fakeAdminPaymentRepo{payouts: map[string]paymentdomain.Payout{}}
}

func (r *fakeAdminPaymentRepo) GetPayout(_ context.Context, id string) (*paymentdomain.Payout, error) {
	p, ok := r.payouts[id]
	if !ok {
		return nil, paymentdomain.ErrPayoutNotFound
	}
	return &p, nil
}

func (r *fakeAdminPaymentRepo) ApprovePayout(_ context.Context, payoutID, moderatorID, providerPayoutID string, now time.Time) (*paymentdomain.Payout, error) {
	r.approveCalls++
	r.lastModerator = moderatorID
	p, ok := r.payouts[payoutID]
	if !ok {
		return nil, paymentdomain.ErrPayoutNotFound
	}
	if p.Status == paymentdomain.PayoutStatusPaid {
		return &p, nil
	}
	p.Status = paymentdomain.PayoutStatusPaid
	p.UpdatedAt = now
	r.payouts[payoutID] = p
	return &p, nil
}

func (r *fakeAdminPaymentRepo) RejectPayout(_ context.Context, payoutID, moderatorID, reason string, now time.Time) (*paymentdomain.Payout, error) {
	r.rejectCalls++
	r.lastModerator = moderatorID
	r.lastRejectReason = reason
	p, ok := r.payouts[payoutID]
	if !ok {
		return nil, paymentdomain.ErrPayoutNotFound
	}
	p.Status = paymentdomain.PayoutStatusCancelled
	p.FailureReason = &reason
	p.UpdatedAt = now
	r.payouts[payoutID] = p
	return &p, nil
}

func (r *fakeAdminPaymentRepo) ListAdminRefunds(_ context.Context, filter paymentdomain.AdminRefundFilter) ([]paymentdomain.Refund, int64, error) {
	r.lastRefundFilter = filter
	return r.refunds, int64(len(r.refunds)), nil
}

func newAdminFinanceUseCase(repo *fakeAdminPaymentRepo, now time.Time) *FinanceUseCase {
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &fakePricingService{}, &fakePaymentProvider{}, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)
}

