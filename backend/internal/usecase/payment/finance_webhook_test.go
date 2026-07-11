package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

type webhookRepo struct {
	noopFinanceRepo
	processed              map[string]bool
	updatePaymentCalls     int
	activateSubCalls       int
	activatePaymentMethods int
	markProcessedCalls     int

	purposeOnUpdate paymentdomain.PaymentPurpose
	statusOnUpdate  paymentdomain.PaymentStatus
}

func newWebhookRepo() *webhookRepo {
	return &webhookRepo{processed: map[string]bool{}}
}

func (r *webhookRepo) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	return fn(r)
}

func (r *webhookRepo) CheckProcessed(_ context.Context, eventID, provider, eventType string, payload []byte) (bool, error) {
	if r.processed[eventID] {
		return true, nil
	}
	r.processed[eventID] = true
	return false, nil
}

func (r *webhookRepo) UpdatePaymentFromProvider(_ context.Context, _, status string, _ bool) (*paymentdomain.Payment, error) {
	r.updatePaymentCalls++
	return &paymentdomain.Payment{
		ID:      "payment-1",
		Purpose: r.purposeOnUpdate,
		Status:  paymentdomain.PaymentStatus(status),
	}, nil
}

func (r *webhookRepo) ActivateSubscriptionByPayment(context.Context, string) error {
	r.activateSubCalls++
	return nil
}

func (r *webhookRepo) ActivatePaymentMethodFromProvider(context.Context, string, string, string, string, int, int, string) error {
	r.activatePaymentMethods++
	return nil
}

func (r *webhookRepo) MarkProcessed(context.Context, string) error {
	r.markProcessedCalls++
	return nil
}

func (r *webhookRepo) CompleteOrderFinancially(context.Context, string, string, int, int) error {
	return nil
}

func newWebhookUC(repo paymentdomain.Repository) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, &scriptedProvider{}, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)
}

func TestHandleWebhookAcceptsValidPayload(t *testing.T) {
	repo := newWebhookRepo()
	repo.purposeOnUpdate = paymentdomain.PaymentPurposeOrder
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true,"metadata":{"purpose":"order","order_id":"order-1"}}}`)

	err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.updatePaymentCalls != 1 {
		t.Errorf("UpdatePaymentFromProvider calls = %d, want 1", repo.updatePaymentCalls)
	}
	if repo.markProcessedCalls != 1 {
		t.Errorf("MarkProcessed calls = %d, want 1", repo.markProcessedCalls)
	}
}

func TestHandleWebhookRejectsMalformedJSON(t *testing.T) {
	repo := newWebhookRepo()
	uc := newWebhookUC(repo)
	payload := []byte(`{not valid json`)

	err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err == nil {
		t.Fatal("expected JSON parse error, got nil")
	}
}

func TestHandleWebhookDuplicateIsIgnored(t *testing.T) {
	repo := newWebhookRepo()
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err != nil {
		t.Fatalf("first call err = %v", err)
	}
	err = uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err != nil {
		t.Fatalf("duplicate call err = %v", err)
	}
	if repo.updatePaymentCalls != 1 {
		t.Errorf("UpdatePaymentFromProvider calls = %d, want 1 (only first call should update)", repo.updatePaymentCalls)
	}
}

func TestHandleWebhookRequeriedStatusFromAPI(t *testing.T) {
	provider := &scriptedProvider{
		getPaymentFn: func(_ context.Context, id string) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{ID: id, Status: "canceled", Paid: false}, nil
		},
	}
	repo := newWebhookRepo()
	repo.purposeOnUpdate = paymentdomain.PaymentPurposeOrder
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, provider, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)

	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if len(provider.getPaymentIDs) != 1 {
		t.Fatalf("GetPayment calls = %d, want 1", len(provider.getPaymentIDs))
	}
	if provider.getPaymentIDs[0] != "p-1" {
		t.Errorf("GetPayment called with id = %q, want %q", provider.getPaymentIDs[0], "p-1")
	}
	if repo.updatePaymentCalls != 1 {
		t.Errorf("UpdatePaymentFromProvider calls = %d, want 1", repo.updatePaymentCalls)
	}
}

func TestHandleWebhookSubscriptionSucceededActivates(t *testing.T) {
	repo := newWebhookRepo()
	repo.purposeOnUpdate = paymentdomain.PaymentPurposeSubscription
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true,"metadata":{"purpose":"subscription"}}}`)

	if err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload); err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.activateSubCalls != 1 {
		t.Errorf("ActivateSubscriptionByPayment calls = %d, want 1 for succeeded subscription payment", repo.activateSubCalls)
	}
}

func TestHandleWebhookUnknownEventTypeIsTolerated(t *testing.T) {
	repo := newWebhookRepo()
	repo.purposeOnUpdate = paymentdomain.PaymentPurposeOrder
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.something_new","object":{"id":"p-1","status":"pending","paid":false}}`)

	err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err != nil {
		t.Fatalf("unknown event_type should not produce an error, got: %v", err)
	}
	if repo.updatePaymentCalls != 1 {
		t.Errorf("UpdatePaymentFromProvider calls = %d, want 1 (provider state still updated)", repo.updatePaymentCalls)
	}
	if repo.activateSubCalls != 0 {
		t.Errorf("ActivateSubscription should not fire for order payment, calls = %d", repo.activateSubCalls)
	}
	if repo.activatePaymentMethods != 0 {
		t.Errorf("ActivatePaymentMethod should not fire for order payment, calls = %d", repo.activatePaymentMethods)
	}
}

func TestHandleWebhookProviderErrorIsReturned(t *testing.T) {
	provider := &scriptedProvider{
		getPaymentFn: func(_ context.Context, id string) (*ProviderPaymentResponse, error) {
			return nil, errors.New("upstream error")
		},
	}
	repo := newWebhookRepo()
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, provider, &fakeSettingsRepo{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleProviderWebhook(context.Background(), NewYooKassaVerifier(), payload)
	if err == nil {
		t.Fatal("expected error when GetPayment fails, got nil")
	}
}
