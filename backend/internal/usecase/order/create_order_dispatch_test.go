package order

import (
	"context"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

// Additional create_order coverage on top of create_order_adversarial_test.go:
// idempotency-key variants (empty/nil keys) and the AutoDispatch flag, which
// must not change the persisted result because dispatch is asynchronous.

// TestCreateOrder_EmptyOrNilIdempotencyKey_CreatesSeparateOrders verifies
// that an absent/empty idempotency key is not treated as a conflict: repeated
// creations without a key each produce their own new order (the unique
// postgres index guards only non-empty keys — see order_repository.go Create).
func TestCreateOrder_EmptyOrNilIdempotencyKey_CreatesSeparateOrders(t *testing.T) {
	orderRepo := &fakeOrderRepository{orders: make(map[string]*orderdomain.Order), getByKeyOrders: make(map[string]*orderdomain.Order)}
	uc := newCreateUC(orderRepo, &scriptedCreatePricing{totalPrice: 300000})

	for i := 0; i < 2; i++ {
		input := createInput()
		if i == 0 {
			emptyKey := ""
			input.IdempotencyKey = &emptyKey
		}
		ord, err := uc.Execute(context.Background(), input)
		if err != nil {
			t.Fatalf("execute #%d: %v", i, err)
		}
		if ord.Status != orderdomain.StatusSearching {
			t.Fatalf("execute #%d: status = %q, want searching", i, ord.Status)
		}
		if ord.PriceTotal != 300000 {
			t.Fatalf("execute #%d: PriceTotal = %d, want 300000", i, ord.PriceTotal)
		}
	}

	if len(orderRepo.orders) != 2 {
		t.Fatalf("expected 2 orders in repository, got %d", len(orderRepo.orders))
	}
	ids := make(map[string]struct{})
	for id := range orderRepo.orders {
		ids[id] = struct{}{}
	}
	if len(ids) != 2 {
		t.Fatalf("expected 2 distinct order ids, got %d (%v)", len(ids), ids)
	}
}

// TestCreateOrder_AutoDispatchFlagDoesNotChangeCreation verifies that the
// AutoDispatch flag is orthogonal to order creation: with either value the
// order is created identically (price fixed, status searching, no driver)
// because dispatch runs asynchronously in the scheduler, never inline.
func TestCreateOrder_AutoDispatchFlagDoesNotChangeCreation(t *testing.T) {
	for _, autoDispatch := range []bool{true, false} {
		t.Run("auto="+boolStr(autoDispatch), func(t *testing.T) {
			orderRepo := &fakeOrderRepository{}
			publisher := &fakeEventPublisher{}
			uc := NewCreateOrderUseCase(orderRepo, &scriptedCreatePricing{totalPrice: 300000}, publisher,
				fakeClock{now: time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)}, &seqIDGen{}, fakeLogger{})

			input := createInput()
			input.AutoDispatch = autoDispatch
			ord, err := uc.Execute(context.Background(), input)
			if err != nil {
				t.Fatalf("Execute: %v", err)
			}
			if ord.Status != orderdomain.StatusSearching {
				t.Fatalf("status = %q, want searching", ord.Status)
			}
			if ord.DriverID != nil {
				t.Fatalf("DriverID = %v, want nil (dispatch must be async)", *ord.DriverID)
			}
			stored, err := orderRepo.GetByID(context.Background(), ord.ID)
			if err != nil {
				t.Fatalf("GetByID: %v", err)
			}
			if stored.Status != orderdomain.StatusSearching || stored.PriceTotal != 300000 {
				t.Fatalf("persisted = %q/%d, want searching/300000", stored.Status, stored.PriceTotal)
			}
		})
	}
}

func boolStr(b bool) string {
	if b {
		return "true"
	}
	return "false"
}
