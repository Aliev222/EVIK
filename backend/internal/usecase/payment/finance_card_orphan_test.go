package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

// Card-flow consistency tests. The core guarantee we test: the local payment
// record is pre-inserted BEFORE the provider is called, so a local insert
// failure can never produce an orphaned provider payment (money at YooKassa
// with no local record in our database).

type failingInsertRepo struct {
	noopFinanceRepo
	err error
}

func (r *failingInsertRepo) CreateOrderPayment(context.Context, *paymentdomain.Payment) (*paymentdomain.Payment, error) {
	return nil, r.err
}

// TestCreateOrderPaymentCard_InsertFailureDoesNotCallProvider proves the
// "orphan excluded" property: when the local insert fails, the provider is
// never contacted, so no payment exists at the provider without a local row.
func TestCreateOrderPaymentCard_InsertFailureDoesNotCallProvider(t *testing.T) {
	insertErr := errors.New("insert rejected")
	repo := &failingInsertRepo{err: insertErr}
	provider := &scriptedProvider{}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	_, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if !errors.Is(err, insertErr) {
		t.Fatalf("err = %v, want insert error", err)
	}
	if len(provider.paymentCalls) != 0 {
		t.Fatalf("provider calls = %d, want 0 (provider must not be called when local insert fails)", len(provider.paymentCalls))
	}
}

type preAttachedRepo struct {
	noopFinanceRepo
	payment *paymentdomain.Payment
}

func (r *preAttachedRepo) CreateOrderPayment(context.Context, *paymentdomain.Payment) (*paymentdomain.Payment, error) {
	return r.payment, nil
}

// TestCreateOrderPaymentCard_AlreadyAttachedSkipsProvider proves the retry
// path: if the pending record was already stamped with a provider id by a
// previous attempt, a repeated confirm must NOT call the provider again
// (no second payment object at the provider).
func TestCreateOrderPaymentCard_AlreadyAttachedSkipsProvider(t *testing.T) {
	pid := "provider-keep"
	attached := &paymentdomain.Payment{
		ID:                "order-payment-1",
		ProviderPaymentID: &pid,
		Status:            paymentdomain.PaymentStatusPending,
		IdempotencyKey:    "order_payment:order-42:card",
	}
	repo := &preAttachedRepo{payment: attached}
	provider := &scriptedProvider{}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	got, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if got == nil || got.ProviderPaymentID == nil || *got.ProviderPaymentID != pid {
		t.Fatalf("payment = %+v, want pre-attached provider id %q", got, pid)
	}
	if len(provider.paymentCalls) != 0 {
		t.Fatalf("provider calls = %d, want 0 (already attached, recovery must skip provider)", len(provider.paymentCalls))
	}
}

type attachErrorRepo struct {
	noopFinanceRepo
	attachErr   error
	attachCalls int
	created     *paymentdomain.Payment
}

func (r *attachErrorRepo) CreateOrderPayment(_ context.Context, p *paymentdomain.Payment) (*paymentdomain.Payment, error) {
	r.created = p
	return p, nil
}

func (r *attachErrorRepo) AttachProviderPayment(context.Context, string, string, string, *string, *time.Time) (*paymentdomain.Payment, error) {
	r.attachCalls++
	return nil, r.attachErr
}

// TestCreateOrderPaymentCard_AttachFailureStillHasLocalAnchor verifies that
// even when stamping the provider data fails, the local pending record was
// already persisted before the provider call, so there is no orphaned money:
// the webhook/retry can always attach the same provider payment (idempotent
// key) onto the existing row.
func TestCreateOrderPaymentCard_AttachFailureStillHasLocalAnchor(t *testing.T) {
	wantErr := errors.New("attach failed")
	repo := &attachErrorRepo{attachErr: wantErr}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{ID: "pp-1", Status: "pending", ConfirmationURL: "https://yookassa.test/pp-1"}, nil
		},
	}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	_, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want attach error", err)
	}
	if repo.created == nil {
		t.Fatal("local pending record must be pre-inserted before contacting the provider")
	}
	if repo.attachCalls != 1 {
		t.Fatalf("attach calls = %d, want 1", repo.attachCalls)
	}
	if len(provider.paymentCalls) != 1 {
		t.Fatalf("provider calls = %d, want 1", len(provider.paymentCalls))
	}
}

type bindingRepo struct {
	noopFinanceRepo
	createPendingCalled bool
	createErr           error
	attachPaymentErr    error
	attachMethodErr     error
	attachCalls         int
}

func (r *bindingRepo) CreatePendingPaymentMethod(context.Context, *paymentdomain.Payment, paymentdomain.PaymentMethod) (*paymentdomain.AddCardInit, error) {
	r.createPendingCalled = true
	return &paymentdomain.AddCardInit{}, r.createErr
}

func (r *bindingRepo) AttachProviderPayment(context.Context, string, string, string, *string, *time.Time) (*paymentdomain.Payment, error) {
	r.attachCalls++
	return nil, r.attachPaymentErr
}

func (r *bindingRepo) AttachPaymentMethodProvider(context.Context, string, string) error {
	return r.attachMethodErr
}

// TestSaveClientPaymentMethod_InsertFailureDoesNotCallProvider extends the
// orphan guarantee to card binding: the local payment+method rows are
// pre-inserted before the (capture-free) provider hold is created.
func TestSaveClientPaymentMethod_InsertFailureDoesNotCallProvider(t *testing.T) {
	repo := &bindingRepo{createErr: errors.New("bind insert failed")}
	provider := &scriptedProvider{}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	_, err := uc.SaveClientPaymentMethod(context.Background(), "client-1")
	if !errors.Is(err, repo.createErr) {
		t.Fatalf("err = %v, want insert error", err)
	}
	if len(provider.paymentCalls) != 0 {
		t.Fatalf("provider calls = %d, want 0 (provider must not be called when local insert fails)", len(provider.paymentCalls))
	}
}

// TestSaveClientPaymentMethod_Ok verifies the happy binding path returns the
// confirmation URL produced by the provider and stamps both local rows.
func TestSaveClientPaymentMethod_Ok(t *testing.T) {
	repo := &bindingRepo{}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{
				ID:              "pp-bind-1",
				Status:          "pending",
				ConfirmationURL: "https://yookassa.test/bind/1",
			}, nil
		},
	}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	init, err := uc.SaveClientPaymentMethod(context.Background(), "client-1")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if !repo.createPendingCalled {
		t.Fatal("CreatePendingPaymentMethod must be called before the provider")
	}
	if init == nil || init.ConfirmationURL != "https://yookassa.test/bind/1" {
		t.Fatalf("init = %+v, want confirmation URL from provider", init)
	}
	if init.PaymentMethodID == "" {
		t.Fatal("payment method id must be returned")
	}
	if repo.attachCalls != 1 {
		t.Fatalf("attach calls = %d, want 1", repo.attachCalls)
	}
	if len(provider.paymentCalls) != 1 {
		t.Fatalf("provider calls = %d, want 1", len(provider.paymentCalls))
	}
}
