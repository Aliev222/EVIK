package payment

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strings"
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

func newWebhookUC(repo paymentdomain.Repository, webhookSecret string) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, &fakePaymentOrderRepo{}, &scriptedPricing{}, &scriptedProvider{}, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, webhookSecret, true)
}

func computeSignature(payload []byte, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	return hex.EncodeToString(mac.Sum(nil))
}

func TestHandleWebhookRejectsInvalidSignature(t *testing.T) {
	repo := &webhookRepo{}
	uc := newWebhookUC(repo, "shared-secret")
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload, "deadbeef")
	if err == nil {
		t.Fatal("expected invalid-signature error, got nil")
	}
	if !strings.Contains(err.Error(), "invalid webhook signature") {
		t.Errorf("error message = %q, want 'invalid webhook signature'", err.Error())
	}
	if repo.storeWebhookCalls != 0 {
		t.Errorf("StoreWebhook should not be called for invalid signature, calls = %d", repo.storeWebhookCalls)
	}
}

func TestHandleWebhookAcceptsValidSignature(t *testing.T) {
	secret := "shared-secret"
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeOrder,
	}
	uc := newWebhookUC(repo, secret)
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true,"metadata":{"purpose":"order","order_id":"order-1"}}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload, computeSignature(payload, secret))
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

func TestHandleWebhookUnknownEventTypeIsTolerated(t *testing.T) {
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeOrder,
	}
	uc := newWebhookUC(repo, "")
	payload := []byte(`{"event":"payment.something_new","object":{"id":"p-1","status":"pending","paid":false}}`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload, "")
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

func TestHandleWebhookSubscriptionSucceededActivates(t *testing.T) {
	repo := &webhookRepo{
		storeWebhookInserted: true,
		purposeOnUpdate:      paymentdomain.PaymentPurposeSubscription,
	}
	uc := newWebhookUC(repo, "")
	payload := []byte(`{"event":"payment.succeeded","object":{"id":"p-1","status":"succeeded","paid":true,"metadata":{"purpose":"subscription"}}}`)

	if err := uc.HandleYooKassaWebhook(context.Background(), payload, ""); err != nil {
		t.Fatalf("err = %v", err)
	}
	if repo.activateSubCalls != 1 {
		t.Errorf("ActivateSubscriptionByPayment calls = %d, want 1 for succeeded subscription payment", repo.activateSubCalls)
	}
}

func TestHandleWebhookMalformedJSON(t *testing.T) {
	repo := &webhookRepo{}
	uc := newWebhookUC(repo, "")
	payload := []byte(`{not valid json`)

	err := uc.HandleYooKassaWebhook(context.Background(), payload, "")
	if err == nil {
		t.Fatal("expected JSON parse error, got nil")
	}
	if repo.storeWebhookCalls != 0 {
		t.Errorf("StoreWebhook should not be called for malformed JSON, calls = %d", repo.storeWebhookCalls)
	}
}
