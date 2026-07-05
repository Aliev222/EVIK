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
	storeWebhookCalls      int
	updatePaymentCalls     int
	activateSubCalls       int
	activatePaymentMethods int
	markProcessedCalls     int

	storeWebhookInserted bool

	purposeOnUpdate paymentdomain.PaymentPurpose
	statusOnUpdate  paymentdomain.PaymentStatus
}

func (r *webhookRepo) StoreWebhook(context.Context, string, string, string, []byte) (bool, error) {
	r.storeWebhookCalls++
	return r.storeWebhookInserted, nil
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

func (r *webhookRepo) MarkWebhookProcessed(context.Context, string) error {
	r.markProcessedCalls++
	return nil
}

func newWebhookUC(repo paymentdomain.Repository) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, &scriptedProvider{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)
}

func TestHandleWebhookAcceptsValidPayload(t *testing.T) {
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeOrder,
	}
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true,"metadata":{"purpose":"order","order_id":"order-1"}}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.storeWebhookCalls != 1 {
		t.Errorf("StoreWebhook calls = %d, want 1", repo.storeWebhookCalls)
	}
	if repo.updatePaymentCalls != 1 {
		t.Errorf("UpdatePaymentFromProvider calls = %d, want 1", repo.updatePaymentCalls)
	}
	if repo.markProcessedCalls != 1 {
		t.Errorf("MarkWebhookProcessed calls = %d, want 1", repo.markProcessedCalls)
	}
}

func TestHandleWebhookRejectsMalformedJSON(t *testing.T) {
	repo := &webhookRepo{}
	uc := newWebhookUC(repo)
	payload := []byte(`{not valid json`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload)
	if err == nil {
		t.Fatal("expected JSON parse error, got nil")
	}
	if repo.storeWebhookCalls != 0 {
		t.Errorf("StoreWebhook should not be called for malformed JSON, calls = %d", repo.storeWebhookCalls)
	}
}

func TestHandleWebhookDuplicateIsIgnored(t *testing.T) {
	repo := &webhookRepo{
		storeWebhookInserted: false,
	}
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.storeWebhookCalls != 1 {
		t.Errorf("StoreWebhook calls = %d, want 1", repo.storeWebhookCalls)
	}
	if repo.updatePaymentCalls != 0 {
		t.Errorf("UpdatePaymentFromProvider should not be called for duplicate webhook")
	}
}

func TestHandleWebhookRequeriedStatusFromAPI(t *testing.T) {
	provider := &scriptedProvider{
		getPaymentFn: func(_ context.Context, id string) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{ID: id, Status: "canceled", Paid: false}, nil
		},
	}
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeOrder,
	}
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, provider, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)

	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload)
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
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeSubscription,
	}
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true,"metadata":{"purpose":"subscription"}}}`)

	if err := uc.HandleYooKassaWebhook(context.Background(), payload); err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.activateSubCalls != 1 {
		t.Errorf("ActivateSubscriptionByPayment calls = %d, want 1 for succeeded subscription payment", repo.activateSubCalls)
	}
}

func TestHandleWebhookUnknownEventTypeIsTolerated(t *testing.T) {
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeOrder,
	}
	uc := newWebhookUC(repo)
	payload := []byte(`{"event":"payment.something_new","object":{"id":"p-1","status":"pending","paid":false}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload)
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
	repo := &webhookRepo{
		storeWebhookInserted: true,
	}
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	uc := NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, provider, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload)
	if err == nil {
		t.Fatal("expected error when GetPayment fails, got nil")
	}
}
