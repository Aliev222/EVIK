package payment

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

type subscriptionRepo struct {
	noopFinanceRepo
	createSubscriptionCalls   int
	createdPayment            *paymentdomain.Payment
	createdSubscription       *paymentdomain.Subscription
	activeSubscription        *paymentdomain.Subscription
	latestSubscription        *paymentdomain.Subscription
	getActiveErr              error
	getLatestErr              error
	createSubscriptionErrHook error
}

func (r *subscriptionRepo) CreateSubscriptionPayment(_ context.Context, p *paymentdomain.Payment, s *paymentdomain.Subscription) (*paymentdomain.Payment, error) {
	r.createSubscriptionCalls++
	r.createdPayment = p
	r.createdSubscription = s
	if r.createSubscriptionErrHook != nil {
		return nil, r.createSubscriptionErrHook
	}
	return p, nil
}

func (r *subscriptionRepo) GetActiveDriverSubscription(context.Context, string) (*paymentdomain.Subscription, error) {
	return r.activeSubscription, r.getActiveErr
}

func (r *subscriptionRepo) GetLatestDriverSubscription(context.Context, string) (*paymentdomain.Subscription, error) {
	return r.latestSubscription, r.getLatestErr
}

func newSubscriptionUC(repo paymentdomain.Repository, provider PaymentProvider, now time.Time) *FinanceUseCase {
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &fakeDriverReleaseStore{}, &scriptedPricing{}, provider, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, nil)
}

func TestCreateDriverSubscriptionPaymentProMonth(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	repo := &subscriptionRepo{}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{ID: "provider-sub-1", Status: "pending"}, nil
		},
	}
	uc := newSubscriptionUC(repo, provider, now)

	payment, err := uc.CreateDriverSubscriptionPayment(context.Background(), "driver-1", "pro_month")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if payment.Amount != 900000 {
		t.Errorf("amount = %d, want 900000 for pro_month plan", payment.Amount)
	}
	if payment.Purpose != paymentdomain.PaymentPurposeSubscription {
		t.Errorf("purpose = %q, want subscription", payment.Purpose)
	}
	if repo.createSubscriptionCalls != 1 {
		t.Errorf("CreateSubscriptionPayment calls = %d, want 1", repo.createSubscriptionCalls)
	}
	if repo.createdSubscription == nil || repo.createdSubscription.PlanID != "pro_month" {
		t.Errorf("subscription planID = %v, want pro_month", repo.createdSubscription)
	}
	wantKey := "subscription:driver-1:pro_month:2026-05"
	if payment.IdempotencyKey != wantKey {
		t.Errorf("IdempotencyKey = %q, want %q", payment.IdempotencyKey, wantKey)
	}
}

func TestCreateDriverSubscriptionPaymentUnknownPlan(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	repo := &subscriptionRepo{}
	uc := newSubscriptionUC(repo, &scriptedProvider{}, now)

	payment, err := uc.CreateDriverSubscriptionPayment(context.Background(), "driver-1", "starter")
	if err == nil {
		t.Fatal("expected error for unknown plan, got nil")
	}
	if payment != nil {
		t.Errorf("expected no payment for unknown plan, got %+v", payment)
	}
	if !strings.Contains(err.Error(), "starter") {
		t.Errorf("error should mention plan name, got: %v", err)
	}
}

func TestCreateDriverSubscriptionPaymentProviderError(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	wantErr := errors.New("yookassa 502")
	repo := &subscriptionRepo{}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return nil, wantErr
		},
	}
	uc := newSubscriptionUC(repo, provider, now)

	_, err := uc.CreateDriverSubscriptionPayment(context.Background(), "driver-1", "pro_month")
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if repo.createSubscriptionCalls != 0 {
		t.Errorf("repo should not be called when provider fails, calls = %d", repo.createSubscriptionCalls)
	}
}

func TestGetDriverSubscriptionStatusActive(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	endsAt := now.Add(10 * 24 * time.Hour)
	repo := &subscriptionRepo{
		activeSubscription: &paymentdomain.Subscription{
			PlanID:   "pro_month",
			Amount:   199000,
			Currency: paymentdomain.CurrencyRUB,
			Status:   paymentdomain.SubscriptionStatusActive,
			EndsAt:   &endsAt,
		},
	}
	uc := newSubscriptionUC(repo, &scriptedProvider{}, now)

	status, err := uc.GetDriverSubscriptionStatus(context.Background(), "driver-1")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if status.Status != "active" {
		t.Errorf("Status = %q, want active", status.Status)
	}
	if !status.CanAcceptOrders {
		t.Error("CanAcceptOrders should be true for active subscription")
	}
	if status.DaysLeft != 10 {
		t.Errorf("DaysLeft = %d, want 10", status.DaysLeft)
	}
}

func TestGetDriverSubscriptionStatusExpired(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	endsAt := now.Add(-24 * time.Hour)
	repo := &subscriptionRepo{
		latestSubscription: &paymentdomain.Subscription{
			PlanID:   "pro_month",
			Amount:   199000,
			Currency: paymentdomain.CurrencyRUB,
			Status:   paymentdomain.SubscriptionStatusExpired,
			EndsAt:   &endsAt,
		},
	}
	uc := newSubscriptionUC(repo, &scriptedProvider{}, now)

	status, err := uc.GetDriverSubscriptionStatus(context.Background(), "driver-1")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if status.Status != "expired" {
		t.Errorf("Status = %q, want expired", status.Status)
	}
	if status.CanAcceptOrders {
		t.Error("CanAcceptOrders should be false for expired subscription")
	}
}

func TestGetDriverSubscriptionStatusNone(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	repo := &subscriptionRepo{} // no active, no latest

	uc := newSubscriptionUC(repo, &scriptedProvider{}, now)

	status, err := uc.GetDriverSubscriptionStatus(context.Background(), "driver-1")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if status.Status != "none" {
		t.Errorf("Status = %q, want none", status.Status)
	}
	if status.CanAcceptOrders {
		t.Error("CanAcceptOrders should be false when no subscription exists")
	}
}

func TestGetDriverSubscriptionStatusActiveLookupError(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	wantErr := errors.New("db error")
	repo := &subscriptionRepo{getActiveErr: wantErr}
	uc := newSubscriptionUC(repo, &scriptedProvider{}, now)

	_, err := uc.GetDriverSubscriptionStatus(context.Background(), "driver-1")
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}

