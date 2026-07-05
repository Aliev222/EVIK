package http

import (
	"context"
	"errors"
	"strings"
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

func TestCreatePayoutLiveModeFailsClosedUntilProviderPayloadsAreImplemented(t *testing.T) {
	client := NewYooKassaClient("shop", "secret", "", "gateway", "payout-secret", "live")

	_, err := client.CreatePayout(context.Background(), YooKassaPayoutRequest{
		Amount:         850000,
		Currency:       "RUB",
		IdempotencyKey: "payout-key-1",
	})
	if err == nil {
		t.Fatal("CreatePayout returned nil error in live mode")
	}
	if !strings.Contains(err.Error(), "card/sbp/bank_account") {
		t.Fatalf("error = %q, want explicit card/sbp/bank_account message", err.Error())
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


