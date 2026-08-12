package order

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	pricingdomain "evik/backend/internal/domain/pricing"
)

// Adversarial coverage for CreateOrderUseCase money invariants: a client must
// never be able to produce an order with a non-positive (zero/negative) price,
// and a failed pricing calculation must not leave a live zero-priced order row.

type scriptedCreatePricing struct {
	totalPrice int64
	err        error
}

func (s *scriptedCreatePricing) CalculatePrice(_ context.Context, input pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error) {
	if s.err != nil {
		return nil, s.err
	}
	return &pricingdomain.PriceCalculation{
		OrderID:    input.OrderID,
		TotalPrice: s.totalPrice,
	}, nil
}

type seqIDGen struct{ n int }

func (g *seqIDGen) NewID() string {
	g.n++
	return "id-" + intStr(g.n)
}

func intStr(n int) string {
	if n == 0 {
		return "0"
	}
	buf := [20]byte{}
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

func newCreateUC(orderRepo *fakeOrderRepository, pricing PricingService) *CreateOrderUseCase {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	return NewCreateOrderUseCase(orderRepo, pricing, &fakeEventPublisher{}, fakeClock{now: now}, &seqIDGen{}, fakeLogger{})
}

func createInput() CreateOrderInput {
	return CreateOrderInput{
		UserID:        "client-1",
		PickupLat:     55.7522,
		PickupLng:     37.6156,
		DropoffLat:    55.7600,
		DropoffLng:    37.6200,
		TowTruckType:  orderdomain.TowTruckWinch,
		PaymentMethod: "cash",
	}
}

// TestCreateOrder_RejectsNonPositivePrice is the adversarial gate for the
// "цена ≤ 0 → заказ не создаётся" invariant: whatever TotalPrice the pricing
// service reports, an order with price <= 0 must never be persisted and must
// never reach 'searching' (dispatch). See bug id CREATE-NONPOSPRICE.
func TestCreateOrder_RejectsNonPositivePrice(t *testing.T) {
	for _, price := range []int64{0, -1, -100000} {
		t.Run("price="+intStr(int(price)), func(t *testing.T) {
			orderRepo := &fakeOrderRepository{}
			uc := newCreateUC(orderRepo, &scriptedCreatePricing{totalPrice: price})

			ord, err := uc.Execute(context.Background(), createInput())
			if err == nil {
				t.Fatal("expected error for non-positive server price, got nil order created")
			}
			if !errors.Is(err, orderdomain.ErrValidationFailed) {
				t.Fatalf("err = %v, want ErrValidationFailed", err)
			}
			if ord != nil {
				t.Fatalf("Execute returned a non-nil order for price %d", price)
			}
			// Nothing may be persisted: no 'created' orphan, no 'searching' row.
			stored, getErr := orderRepo.GetByID(context.Background(), "id-1")
			if getErr == nil && stored != nil {
				t.Fatalf("order with price %d was persisted in status %q", stored.PriceTotal, stored.Status)
			}
			if !errors.Is(getErr, orderdomain.ErrOrderNotFound) {
				t.Fatalf("GetByID: err = %v, want ErrOrderNotFound (nothing persisted)", getErr)
			}
		})
	}
}

// TestCreateOrder_FailedPriceComputationPersistsNothing guards the money
// invariant that a pricing outage must never leave a live zero-priced
// 'created' order row behind (create_order.go prices the order BEFORE the
// first persist). A dispatcher polling 'created'/'searching' orders can only
// ever see rows with a validated positive price.
func TestCreateOrder_FailedPriceComputationPersistsNothing(t *testing.T) {
	orderRepo := &fakeOrderRepository{}
	uc := newCreateUC(orderRepo, &scriptedCreatePricing{err: errors.New("pricing provider down")})

	_, err := uc.Execute(context.Background(), createInput())
	if err == nil {
		t.Fatal("expected error when pricing fails")
	}

	stored, getErr := orderRepo.GetByID(context.Background(), "id-1")
	if getErr == nil && stored != nil {
		t.Fatalf("zero-priced order row was persisted (status %q, price %d)", stored.Status, stored.PriceTotal)
	}
	if !errors.Is(getErr, orderdomain.ErrOrderNotFound) {
		t.Fatalf("GetByID: err = %v, want ErrOrderNotFound (no orphan row)", getErr)
	}
}

// TestCreateOrder_HappyPathPersistsPricedSearchingOrder locks the happy path
// after the price-first reorder: a valid positive price is persisted and the
// order reaches 'searching' with the computed amount.
func TestCreateOrder_HappyPathPersistsPricedSearchingOrder(t *testing.T) {
	orderRepo := &fakeOrderRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewCreateOrderUseCase(orderRepo, &scriptedCreatePricing{totalPrice: 300000}, publisher,
		fakeClock{now: time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)}, &seqIDGen{}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), createInput())
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.PriceTotal != 300000 {
		t.Errorf("PriceTotal = %d, want 300000", ord.PriceTotal)
	}
	if ord.Status != orderdomain.StatusSearching {
		t.Errorf("Status = %q, want searching", ord.Status)
	}

	stored, err := orderRepo.GetByID(context.Background(), ord.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if stored.PriceTotal != 300000 {
		t.Errorf("persisted PriceTotal = %d, want 300000", stored.PriceTotal)
	}
	if stored.Status != orderdomain.StatusSearching {
		t.Errorf("persisted Status = %q, want searching", stored.Status)
	}

	var searchingEvent bool
	for _, ev := range publisher.Events() {
		if ev.Type == orderdomain.EventSearching && ev.OrderID == ord.ID {
			searchingEvent = true
		}
	}
	if !searchingEvent {
		t.Error("expected EventSearching to be published for the created order")
	}
}

// TestCreateOrder_IdempotentKeyRejectedWithoutDuplicate verifies the
// idempotency invariant survives the price-first reorder: a retry with the
// same idempotency key still raises ErrIdempotencyConflict, produces no
// duplicate row and does not touch the originally persisted order.
func TestCreateOrder_IdempotentKeyRejectedWithoutDuplicate(t *testing.T) {
	orderRepo := &fakeOrderRepository{getByKeyOrders: make(map[string]*orderdomain.Order)}
	pricing := &scriptedCreatePricing{totalPrice: 300000}
	uc := newCreateUC(orderRepo, pricing)

	key := "ik-same"
	input := createInput()
	input.IdempotencyKey = &key

	first, err := uc.Execute(context.Background(), input)
	if err != nil {
		t.Fatalf("first Execute: %v", err)
	}
	if first.Status != orderdomain.StatusSearching {
		t.Fatalf("first order status = %q, want searching", first.Status)
	}

	_, err = uc.Execute(context.Background(), input)
	if !errors.Is(err, orderdomain.ErrIdempotencyConflict) {
		t.Fatalf("second Execute: err = %v, want ErrIdempotencyConflict", err)
	}

	// Exactly one order exists under the key, unchanged by the retry.
	existing, err := orderRepo.GetByOrderKey(context.Background(), key)
	if err != nil {
		t.Fatalf("GetByOrderKey: %v", err)
	}
	if existing == nil {
		t.Fatal("GetByOrderKey returned nil")
	}
	if existing.ID != first.ID {
		t.Errorf("retry returned order %s, want original %s", existing.ID, first.ID)
	}
	if existing.Status != orderdomain.StatusSearching {
		t.Errorf("retry mutated stored order status to %q", existing.Status)
	}
	if existing.PriceTotal != 300000 {
		t.Errorf("retry mutated stored order price to %d", existing.PriceTotal)
	}
	if len(orderRepo.getByKeyOrders) != 1 {
		t.Errorf("expected exactly 1 order under the key, got %d", len(orderRepo.getByKeyOrders))
	}
}
