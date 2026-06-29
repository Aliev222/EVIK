package payment

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
)

type createPaymentRepo struct {
	noopFinanceRepo
	createOrderPaymentCalls int
	createdPayment          *paymentdomain.Payment
}

func (r *createPaymentRepo) CreateOrderPayment(_ context.Context, p *paymentdomain.Payment) (*paymentdomain.Payment, error) {
	r.createOrderPaymentCalls++
	r.createdPayment = p
	return p, nil
}

type createPaymentOrderRepo struct {
	order *orderdomain.Order
	err   error
}

func (r *createPaymentOrderRepo) Create(context.Context, *orderdomain.Order) error { return nil }
func (r *createPaymentOrderRepo) Update(context.Context, *orderdomain.Order) error { return nil }
func (r *createPaymentOrderRepo) GetByID(context.Context, string) (*orderdomain.Order, error) {
	if r.err != nil {
		return nil, r.err
	}
	return r.order, nil
}
func (r *createPaymentOrderRepo) ListByStatus(context.Context, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (r *createPaymentOrderRepo) ListAdminOrders(context.Context, orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error) {
	return nil, 0, nil
}
func (r *createPaymentOrderRepo) GetAdminOrderDetails(context.Context, string) (*orderdomain.AdminOrderDetails, error) {
	return nil, nil
}
func (r *createPaymentOrderRepo) AcceptOrder(context.Context, string, string) (*orderdomain.Order, error) {
	return nil, nil
}

func sampleOrder(userID string) *orderdomain.Order {
	return &orderdomain.Order{
		ID:           "order-42",
		UserID:       userID,
		Pickup:       orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:      orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType: orderdomain.TowTruckWinch,
		Status:       orderdomain.StatusAccepted,
	}
}

func newCreatePaymentUC(repo paymentdomain.Repository, orderRepo orderdomain.Repository, pricing PricingService, provider PaymentProvider) *FinanceUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewFinanceUseCase(repo, orderRepo, pricing, provider, fakeClock{now: now}, fakeIDGenerator{}, 600, 10000, "", true)
}

func TestCreateOrderPaymentRejectsInvalidMethod(t *testing.T) {
	repo := &createPaymentRepo{}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		&scriptedProvider{},
	)

	_, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodType("crypto"))
	if !errors.Is(err, paymentdomain.ErrValidationFailed) {
		t.Fatalf("err = %v, want ErrValidationFailed", err)
	}
	if repo.createOrderPaymentCalls != 0 {
		t.Errorf("repo should not be called for invalid method, calls = %d", repo.createOrderPaymentCalls)
	}
}

func TestCreateOrderPaymentRejectsForeignOrder(t *testing.T) {
	repo := &createPaymentRepo{}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("someone-else")},
		&scriptedPricing{totalPrice: 800000},
		&scriptedProvider{},
	)

	_, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if err == nil || err.Error() != "order does not belong to user" {
		t.Fatalf("err = %v, want 'order does not belong to user'", err)
	}
}

func TestCreateOrderPaymentCashMarksSucceededWithoutProvider(t *testing.T) {
	repo := &createPaymentRepo{}
	provider := &scriptedProvider{}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	payment, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCash)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if payment.Status != paymentdomain.PaymentStatusSucceeded {
		t.Errorf("status = %q, want succeeded for cash", payment.Status)
	}
	if payment.PaidAt == nil {
		t.Error("PaidAt should be set for cash payment")
	}
	if payment.ProviderPaymentID == nil || *payment.ProviderPaymentID != "cash:order-42" {
		t.Errorf("ProviderPaymentID = %v, want 'cash:order-42'", payment.ProviderPaymentID)
	}
	if len(provider.paymentCalls) != 0 {
		t.Errorf("provider should not be called for cash, calls = %d", len(provider.paymentCalls))
	}
	if payment.Amount != 800000 {
		t.Errorf("amount = %d, want 800000", payment.Amount)
	}
}

func TestCreateOrderPaymentCardSuccess(t *testing.T) {
	repo := &createPaymentRepo{}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{
				ID:              "provider-x-1",
				Status:          "pending",
				ConfirmationURL: "https://yookassa.test/confirm/x-1",
			}, nil
		},
	}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	payment, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if len(provider.paymentCalls) != 1 {
		t.Fatalf("provider calls = %d, want 1", len(provider.paymentCalls))
	}
	if payment.Status != paymentdomain.PaymentStatusPending {
		t.Errorf("status = %q, want pending", payment.Status)
	}
	if payment.ConfirmationURL == nil || *payment.ConfirmationURL != "https://yookassa.test/confirm/x-1" {
		t.Errorf("ConfirmationURL = %v, want set", payment.ConfirmationURL)
	}
	if payment.ProviderPaymentID == nil || *payment.ProviderPaymentID != "provider-x-1" {
		t.Errorf("ProviderPaymentID = %v, want provider-x-1", payment.ProviderPaymentID)
	}
	if payment.IdempotencyKey != "order_payment:order-42:card" {
		t.Errorf("IdempotencyKey = %q, want order_payment:order-42:card", payment.IdempotencyKey)
	}
}

func TestCreateOrderPaymentCardPaidImmediately(t *testing.T) {
	repo := &createPaymentRepo{}
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return &ProviderPaymentResponse{
				ID:     "provider-x-2",
				Status: "succeeded",
				Paid:   true,
			}, nil
		},
	}
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{totalPrice: 800000},
		provider,
	)

	payment, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if payment.Status != paymentdomain.PaymentStatusSucceeded {
		t.Errorf("status = %q, want succeeded", payment.Status)
	}
	if payment.PaidAt == nil {
		t.Error("PaidAt should be set when provider reports Paid=true")
	}
}

func TestCreateOrderPaymentCardProviderError(t *testing.T) {
	repo := &createPaymentRepo{}
	wantErr := errors.New("provider 500")
	provider := &scriptedProvider{
		createPaymentFn: func(context.Context, ProviderPaymentRequest) (*ProviderPaymentResponse, error) {
			return nil, wantErr
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
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if repo.createOrderPaymentCalls != 0 {
		t.Errorf("repo should not be called when provider fails, calls = %d", repo.createOrderPaymentCalls)
	}
}

func TestCreateOrderPaymentPricingError(t *testing.T) {
	repo := &createPaymentRepo{}
	wantErr := errors.New("no tariff")
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{order: sampleOrder("client-1")},
		&scriptedPricing{err: wantErr},
		&scriptedProvider{},
	)

	_, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}

func TestCreateOrderPaymentOrderLookupError(t *testing.T) {
	repo := &createPaymentRepo{}
	wantErr := errors.New("order vanished")
	uc := newCreatePaymentUC(
		repo,
		&createPaymentOrderRepo{err: wantErr},
		&scriptedPricing{totalPrice: 800000},
		&scriptedProvider{},
	)

	_, err := uc.CreateOrderPayment(context.Background(), "client-1", "order-42", paymentdomain.PaymentMethodCard)
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}
