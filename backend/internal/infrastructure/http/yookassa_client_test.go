package http

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCreatePayoutIsSandboxMockByDefault(t *testing.T) {
	client := NewYooKassaClient("", "", "", "", "", "sandbox")

	payout, err := client.CreatePayout(context.Background(), YooKassaPayoutRequest{
		Amount:         850000,
		Currency:       "RUB",
		IdempotencyKey: "payout-key-1",
	})
	if err != nil {
		t.Fatalf("CreatePayout returned error: %v", err)
	}
	if payout.ID != "sandbox-payout-key-1" {
		t.Fatalf("payout id = %q, want sandbox-payout-key-1", payout.ID)
	}
	if payout.Status != "succeeded" {
		t.Fatalf("status = %q, want succeeded", payout.Status)
	}
}

func TestCreatePayoutLiveModeFailsClosedUntilRecipientOnboardingIsImplemented(t *testing.T) {
	client := NewYooKassaClient("shop", "secret", "", "", "", "live")
	_, err := client.CreatePayout(context.Background(), YooKassaPayoutRequest{
		Amount:              500,
		Currency:            "RUB",
		ProviderRecipientID: "pm-saved-1",
		IdempotencyKey:      "payout-key-1",
	})
	if err == nil {
		t.Fatal("CreatePayout returned nil error in live mode")
	}
}

func TestGetPayoutUsesGatewayCredentials(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/payouts/po-1" {
			t.Fatalf("request = %s %s", r.Method, r.URL.Path)
		}
		user, password, ok := r.BasicAuth()
		if !ok || user != "gateway" || password != "payout-secret" {
			t.Fatalf("unexpected payout auth: %q %q %v", user, password, ok)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"po-1","status":"succeeded"}`))
	}))
	defer server.Close()

	client := NewYooKassaClient("shop", "secret", "", "gateway", "payout-secret", "live")
	client.baseURL = server.URL
	payout, err := client.GetPayout(context.Background(), "po-1")
	if err != nil {
		t.Fatalf("GetPayout error: %v", err)
	}
	if payout.ID != "po-1" || payout.Status != "succeeded" {
		t.Fatalf("payout = %#v", payout)
	}
}

func TestCreatePaymentMissingCredentialsReturnsTypedError(t *testing.T) {
	client := NewYooKassaClient("", "", "", "", "", "sandbox")

	_, err := client.CreatePayment(context.Background(), YooKassaPaymentRequest{
		Amount:         100000,
		Currency:       "RUB",
		IdempotencyKey: "pay-key-1",
	})
	if !errors.Is(err, ErrCredentialsNotConfigured) {
		t.Fatalf("error = %v, want ErrCredentialsNotConfigured", err)
	}
}
