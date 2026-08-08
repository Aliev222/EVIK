package order

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

func newFinalizeUC(order *orderdomain.Order) (*FinalizeOrderUseCase, *fakeOrderRepository) {
	orderRepo := &fakeOrderRepository{order: order}
	publisher := &fakeEventPublisher{}
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	uc := NewFinalizeOrderUseCase(orderRepo, publisher, nil, fakeClock{now: now}, fakeLogger{})
	return uc, orderRepo
}

// TestFinalizeUsesServerPrice guards the normal app flow: the driver app sends
// back the server-computed price and the order completes to awaiting_payment
// with that exact total.
func TestFinalizeUsesServerPrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(&orderdomain.Order{
		ID:         "order-1",
		UserID:     "client-1",
		DriverID:   &driverID,
		Status:     orderdomain.StatusInProgress,
		PriceTotal: 500000,
	})

	ord, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusAwaitingPayment {
		t.Fatalf("status = %q, want %q", ord.Status, orderdomain.StatusAwaitingPayment)
	}
	if ord.PriceTotal != 500000 {
		t.Fatalf("price_total = %d, want 500000 (server price)", ord.PriceTotal)
	}
	if !orderRepo.updated {
		t.Fatal("order was not persisted after finalize")
	}
}

// TestFinalizeIgnoresCallerPriceWithinTolerance proves the caller's number is
// only validated, never written: even a slightly-off final_price (within the
// rounding tolerance) leaves the server-computed total untouched.
func TestFinalizeIgnoresCallerPriceWithinTolerance(t *testing.T) {
	driverID := "driver-1"
	uc, _ := newFinalizeUC(&orderdomain.Order{
		ID:         "order-1",
		UserID:     "client-1",
		DriverID:   &driverID,
		Status:     orderdomain.StatusInProgress,
		PriceTotal: 500000,
	})

	ord, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500100,
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.PriceTotal != 500000 {
		t.Fatalf("price_total = %d, want 500000 (caller value must be ignored)", ord.PriceTotal)
	}
}

// TestFinalizeRejectsInflatedPrice guards the money hole: a caller-supplied
// final_price above the server price (beyond tolerance) must be rejected and
// must never be persisted.
func TestFinalizeRejectsInflatedPrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(&orderdomain.Order{
		ID:         "order-1",
		UserID:     "client-1",
		DriverID:   &driverID,
		Status:     orderdomain.StatusInProgress,
		PriceTotal: 500000,
	})

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 1000000,
	})
	if !errors.Is(err, ErrFinalPriceMismatch) {
		t.Fatalf("error = %v, want ErrFinalPriceMismatch", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated for an inflated final price")
	}
	persisted, getErr := orderRepo.GetByID(context.Background(), "order-1")
	if getErr != nil {
		t.Fatalf("GetByID failed: %v", getErr)
	}
	if persisted.Status != orderdomain.StatusInProgress {
		t.Fatalf("status = %q, want still %q", persisted.Status, orderdomain.StatusInProgress)
	}
	if persisted.PriceTotal != 500000 {
		t.Fatalf("price_total = %d, want 500000 (inflated price must not be stored)", persisted.PriceTotal)
	}
}

// TestFinalizeRejectsUnderpricedPrice guards underpricing as well: the caller
// must not be able to move the completion price below the server price either.
func TestFinalizeRejectsUnderpricedPrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(&orderdomain.Order{
		ID:         "order-1",
		UserID:     "client-1",
		DriverID:   &driverID,
		Status:     orderdomain.StatusInProgress,
		PriceTotal: 500000,
	})

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 100,
	})
	if !errors.Is(err, ErrFinalPriceMismatch) {
		t.Fatalf("error = %v, want ErrFinalPriceMismatch", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated for an underpriced final price")
	}
}

// TestFinalizeRequiresPositivePrice preserves the existing positive-price
// validation on the caller-supplied value.
func TestFinalizeRequiresPositivePrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(&orderdomain.Order{
		ID:         "order-1",
		UserID:     "client-1",
		DriverID:   &driverID,
		Status:     orderdomain.StatusInProgress,
		PriceTotal: 500000,
	})

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 0,
	})
	if err == nil {
		t.Fatal("expected error for non-positive final_price")
	}
	if orderRepo.updated {
		t.Fatal("order was updated for a non-positive final price")
	}
}

// TestFinalizeRejectsOrderWithoutServerPrice guards the case where no
// server-computed price exists: the order must not be finalized with an
// arbitrary caller number.
func TestFinalizeRejectsOrderWithoutServerPrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(&orderdomain.Order{
		ID:         "order-1",
		UserID:     "client-1",
		DriverID:   &driverID,
		Status:     orderdomain.StatusInProgress,
		PriceTotal: 0,
	})

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	})
	if !errors.Is(err, orderdomain.ErrValidationFailed) {
		t.Fatalf("error = %v, want ErrValidationFailed", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated without a server-computed price")
	}
}
