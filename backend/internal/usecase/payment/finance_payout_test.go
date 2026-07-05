package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

type payoutRepo struct {
	noopFinanceRepo
	payoutMethods       []paymentdomain.DriverPayoutMethod
	listMethodsErr      error
	createPayoutErr     error
	markPayoutFailedArg struct {
		called  bool
		payoutID string
		reason   string
	}
}

func (r *payoutRepo) ListPayoutMethods(_ context.Context, _ string) ([]paymentdomain.DriverPayoutMethod, error) {
	if r.listMethodsErr != nil {
		return nil, r.listMethodsErr
	}
	return r.payoutMethods, nil
}

func (r *payoutRepo) CreatePayout(_ context.Context, p *paymentdomain.Payout, idempotencyKey string) (*paymentdomain.Payout, error) {
	if r.createPayoutErr != nil {
		return nil, r.createPayoutErr
	}
	p.IdempotencyKey = idempotencyKey
	return p, nil
}

func (r *payoutRepo) MarkPayoutFailed(_ context.Context, payoutID, reason string) error {
	r.markPayoutFailedArg.called = true
	r.markPayoutFailedArg.payoutID = payoutID
	r.markPayoutFailedArg.reason = reason
	return nil
}

func newPayoutUC(repo paymentdomain.Repository, provider PaymentProvider) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, provider, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)
}

func TestRequestDriverPayoutRejectsNonPositiveAmount(t *testing.T) {
	repo := &payoutRepo{}
	uc := newPayoutUC(repo, &scriptedProvider{})

	for _, amount := range []int64{0, -1, -100000} {
		t.Run("amount="+intToStr(int(amount)), func(t *testing.T) {
			_, err := uc.RequestDriverPayout(context.Background(), "driver-1", amount, "key")
			if !errors.Is(err, paymentdomain.ErrInvalidAmount) {
				t.Fatalf("err = %v, want ErrInvalidAmount", err)
			}
		})
	}
}

func TestRequestDriverPayoutNoDefaultMethod(t *testing.T) {
	tests := []struct {
		name    string
		methods []paymentdomain.DriverPayoutMethod
	}{
		{
			name:    "empty list",
			methods: nil,
		},
		{
			name: "method exists but not default",
			methods: []paymentdomain.DriverPayoutMethod{
				{ID: "m-1", DriverID: "driver-1", IsDefault: false, Status: "active"},
			},
		},
		{
			name: "default method exists but inactive",
			methods: []paymentdomain.DriverPayoutMethod{
				{ID: "m-1", DriverID: "driver-1", IsDefault: true, Status: "blocked"},
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			repo := &payoutRepo{payoutMethods: tc.methods}
			provider := &scriptedProvider{}
			uc := newPayoutUC(repo, provider)

			_, err := uc.RequestDriverPayout(context.Background(), "driver-1", 850000, "key-1")
			if !errors.Is(err, paymentdomain.ErrPayoutMethodNotFound) {
				t.Fatalf("err = %v, want ErrPayoutMethodNotFound", err)
			}
			if len(provider.payoutCalls) != 0 {
				t.Errorf("provider should not be called without default method, calls = %d", len(provider.payoutCalls))
			}
			if repo.markPayoutFailedArg.called {
				t.Error("MarkPayoutFailed should not be called when payout was never created")
			}
		})
	}
}

func TestRequestDriverPayoutListMethodsError(t *testing.T) {
	wantErr := errors.New("db down")
	repo := &payoutRepo{listMethodsErr: wantErr}
	uc := newPayoutUC(repo, &scriptedProvider{})

	_, err := uc.RequestDriverPayout(context.Background(), "driver-1", 850000, "key-1")
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}

func TestRequestDriverPayoutCreatePayoutRepoError(t *testing.T) {
	wantErr := errors.New("constraint violation")
	repo := &payoutRepo{
		payoutMethods: []paymentdomain.DriverPayoutMethod{
			{ID: "m-1", DriverID: "driver-1", IsDefault: true, Status: "active", ProviderRecipientID: "recipient-1"},
		},
		createPayoutErr: wantErr,
	}
	provider := &scriptedProvider{}
	uc := newPayoutUC(repo, provider)

	_, err := uc.RequestDriverPayout(context.Background(), "driver-1", 850000, "key-1")
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if len(provider.payoutCalls) != 0 {
		t.Errorf("provider should not be called when repo CreatePayout failed, calls = %d", len(provider.payoutCalls))
	}
}

func TestRequestDriverPayoutProviderErrorMarksFailed(t *testing.T) {
	wantErr := errors.New("yookassa 503")
	repo := &payoutRepo{
		payoutMethods: []paymentdomain.DriverPayoutMethod{
			{ID: "m-1", DriverID: "driver-1", IsDefault: true, Status: "active", ProviderRecipientID: "recipient-1"},
		},
	}
	provider := &scriptedProvider{
		createPayoutFn: func(context.Context, ProviderPayoutRequest) (*ProviderPayoutResponse, error) {
			return nil, wantErr
		},
	}
	uc := newPayoutUC(repo, provider)

	_, err := uc.RequestDriverPayout(context.Background(), "driver-1", 850000, "key-1")
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if !repo.markPayoutFailedArg.called {
		t.Fatal("MarkPayoutFailed must be called when provider fails")
	}
	if repo.markPayoutFailedArg.reason != wantErr.Error() {
		t.Errorf("MarkPayoutFailed reason = %q, want %q", repo.markPayoutFailedArg.reason, wantErr.Error())
	}
	if repo.markPayoutFailedArg.payoutID == "" {
		t.Error("MarkPayoutFailed should receive non-empty payout ID")
	}
}

func TestRequestDriverPayoutAutoIdempotencyKey(t *testing.T) {
	repo := &payoutRepo{
		payoutMethods: []paymentdomain.DriverPayoutMethod{
			{ID: "m-1", DriverID: "driver-1", IsDefault: true, Status: "active", ProviderRecipientID: "recipient-1"},
		},
	}
	provider := &scriptedProvider{}
	uc := newPayoutUC(repo, provider)

	payout, err := uc.RequestDriverPayout(context.Background(), "driver-1", 850000, "")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if payout.IdempotencyKey == "" {
		t.Fatal("empty idempotency key should be auto-generated, got empty result")
	}
}
