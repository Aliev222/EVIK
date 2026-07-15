package payment

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

type releaseRepo struct {
	noopFinanceRepo
	pending      []paymentdomain.WalletTransaction
	listLimitArg int
	listErr      error
	failOnID     string
	released     []string
}

func (r *releaseRepo) ListReleasablePendingTransactions(_ context.Context, limit int) ([]paymentdomain.WalletTransaction, error) {
	r.listLimitArg = limit
	if r.listErr != nil {
		return nil, r.listErr
	}
	return r.pending, nil
}

func (r *releaseRepo) MarkTransactionReleased(_ context.Context, id string) error {
	if id == r.failOnID {
		return errors.New("locked")
	}
	r.released = append(r.released, id)
	return nil
}

func newReleaseUC(repo paymentdomain.Repository) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &scriptedPricing{}, &scriptedProvider{}, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)
}

func TestReleasePendingBalancesEmptyList(t *testing.T) {
	repo := &releaseRepo{}
	uc := newReleaseUC(repo)

	count, err := uc.ReleasePendingBalances(context.Background(), 50)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if count != 0 {
		t.Errorf("count = %d, want 0", count)
	}
	if repo.listLimitArg != 50 {
		t.Errorf("limit passed to repo = %d, want 50", repo.listLimitArg)
	}
}

func TestReleasePendingBalancesAllSucceed(t *testing.T) {
	repo := &releaseRepo{
		pending: []paymentdomain.WalletTransaction{
			{ID: "tx-1"},
			{ID: "tx-2"},
			{ID: "tx-3"},
		},
	}
	uc := newReleaseUC(repo)

	count, err := uc.ReleasePendingBalances(context.Background(), 100)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if count != 3 {
		t.Errorf("count = %d, want 3", count)
	}
	if len(repo.released) != 3 {
		t.Errorf("released = %d, want 3", len(repo.released))
	}
}

func TestReleasePendingBalancesPartialFailure(t *testing.T) {
	repo := &releaseRepo{
		pending: []paymentdomain.WalletTransaction{
			{ID: "tx-1"},
			{ID: "tx-2"},
			{ID: "tx-3"},
		},
		failOnID: "tx-2",
	}
	uc := newReleaseUC(repo)

	count, err := uc.ReleasePendingBalances(context.Background(), 100)
	if err == nil {
		t.Fatal("expected error for partial failure, got nil")
	}
	if count != 2 {
		t.Errorf("count = %d, want 2 (the two that succeeded)", count)
	}
	if !strings.Contains(err.Error(), "tx-2") {
		t.Errorf("error should mention failing tx-2, got: %v", err)
	}
}

func TestReleasePendingBalancesListErrorIsReturned(t *testing.T) {
	wantErr := errors.New("db down")
	repo := &releaseRepo{listErr: wantErr}
	uc := newReleaseUC(repo)

	count, err := uc.ReleasePendingBalances(context.Background(), 100)
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if count != 0 {
		t.Errorf("count = %d, want 0 on list failure", count)
	}
}

func TestReleasePendingBalancesNonPositiveLimitFallsBackTo100(t *testing.T) {
	tests := []struct {
		name  string
		limit int
	}{
		{"zero", 0},
		{"negative", -5},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			repo := &releaseRepo{}
			uc := newReleaseUC(repo)
			_, err := uc.ReleasePendingBalances(context.Background(), tc.limit)
			if err != nil {
				t.Fatalf("err = %v", err)
			}
			if repo.listLimitArg != 100 {
				t.Errorf("limit passed to repo = %d, want 100 (fallback default)", repo.listLimitArg)
			}
		})
	}
}

