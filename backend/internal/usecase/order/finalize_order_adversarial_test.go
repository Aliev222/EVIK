package order

import (
	"context"
	"errors"
	"strings"
	"testing"

	orderdomain "evik/backend/internal/domain/order"
)

// Adversarial/edge coverage for FinalizeOrderUseCase on top of
// finalize_order_test.go. The tolerance is finalPriceToleranceKopecks = 100
// (= 1 ruble in kopecks), so the boundary is exactly ±100.

func finalizeOrderInProgress(driverID string) *orderdomain.Order {
	return &orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "card",
	}
}

// TestFinalizeRejectsNegativePrice verifies a negative final_price is refused
// before any persistence. (Zero is already covered by
// TestFinalizeRequiresPositivePrice.)
func TestFinalizeRejectsNegativePrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(finalizeOrderInProgress(driverID))

	for _, price := range []int64{-1, -100000} {
		_, err := uc.Execute(context.Background(), FinalizeOrderInput{
			OrderID:    "order-1",
			DriverID:   driverID,
			FinalPrice: price,
		})
		if err == nil {
			t.Fatalf("final_price=%d: expected error, got nil", price)
		}
		if orderRepo.updated {
			t.Fatalf("final_price=%d: order was updated", price)
		}
	}
}

// TestFinalizeRejectsPriceOneRubleAboveTolerance verifies a final_price a
// full ruble (100 kopecks) ABOVE the tolerance band is rejected. With
// tolerance = 100, serverPrice = 500000, a caller price of 500200 deviates by
// 200 kopecks → must fail.
func TestFinalizeRejectsPriceOneRubleAboveTolerance(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(finalizeOrderInProgress(driverID))

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500200, // server + 2 rubles worth of kopecks, diff 200 > 100
	})
	if !errors.Is(err, ErrFinalPriceMismatch) {
		t.Fatalf("err = %v, want ErrFinalPriceMismatch", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated for a price above the tolerance band")
	}
}

// TestFinalizeRejectsPriceOneRubleBelowTolerance mirrors the above for the
// underpriced direction: a caller price 200 kopecks below the server price
// must be rejected.
func TestFinalizeRejectsPriceOneRubleBelowTolerance(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(finalizeOrderInProgress(driverID))

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 499800, // diff 200 > 100
	})
	if !errors.Is(err, ErrFinalPriceMismatch) {
		t.Fatalf("err = %v, want ErrFinalPriceMismatch", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated for a price below the tolerance band")
	}
}

// TestFinalizeRejectsPriceJustBeyondTolerance verifies the razor edge: a
// deviation of exactly tolerance+1 kopecks (101) is rejected.
func TestFinalizeRejectsPriceJustBeyondTolerance(t *testing.T) {
	driverID := "driver-1"
	uc, _ := newFinalizeUC(finalizeOrderInProgress(driverID))

	tests := []int64{500101, 499899}
	for _, price := range tests {
		_, err := uc.Execute(context.Background(), FinalizeOrderInput{
			OrderID:    "order-1",
			DriverID:   driverID,
			FinalPrice: price,
		})
		if !errors.Is(err, ErrFinalPriceMismatch) {
			t.Fatalf("final_price=%d: err = %v, want ErrFinalPriceMismatch", price, err)
		}
	}
}

// TestFinalizeAcceptsPriceAtToleranceBoundary verifies that a deviation of
// exactly the tolerance (100 kopecks = 1 ruble) is ACCEPTED and the
// server-computed price is kept untouched.
func TestFinalizeAcceptsPriceAtToleranceBoundary(t *testing.T) {
	driverID := "driver-1"
	uc, _ := newFinalizeUC(finalizeOrderInProgress(driverID))

	ord, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 499900, // server - 100 kopecks = exactly the tolerance
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusAwaitingPayment {
		t.Fatalf("status = %q, want %q", ord.Status, orderdomain.StatusAwaitingPayment)
	}
	if ord.PriceTotal != 500000 {
		t.Fatalf("price_total = %d, want 500000 (server price, caller value ignored)", ord.PriceTotal)
	}
}

// TestFinalizeRejectsNonInProgressStatus verifies finalize only runs from
// in_progress: any other status must be rejected with ErrInvalidTransition
// before money/persistence logic is touched.
func TestFinalizeRejectsNonInProgressStatus(t *testing.T) {
	driverID := "driver-1"
	statuses := []orderdomain.Status{
		orderdomain.StatusCreated,
		orderdomain.StatusSearching,
		orderdomain.StatusAccepted,
		orderdomain.StatusArrived,
		orderdomain.StatusAwaitingPayment,
		orderdomain.StatusCompleted,
		orderdomain.StatusCancelled,
	}
	for _, status := range statuses {
		t.Run(string(status), func(t *testing.T) {
			uc, orderRepo := newFinalizeUC(&orderdomain.Order{
				ID:         "order-1",
				UserID:     "client-1",
				DriverID:   &driverID,
				Status:     status,
				PriceTotal: 500000,
			})
			_, err := uc.Execute(context.Background(), FinalizeOrderInput{
				OrderID:    "order-1",
				DriverID:   driverID,
				FinalPrice: 500000,
			})
			if !errors.Is(err, orderdomain.ErrInvalidTransition) {
				t.Fatalf("err = %v, want ErrInvalidTransition", err)
			}
			if orderRepo.updated {
				t.Fatal("order was updated for a non-in_progress finalize")
			}
		})
	}
}

// TestFinalizeRejectsForeignDriver verifies a driver that does not own the
// order cannot finalize it.
func TestFinalizeRejectsForeignDriver(t *testing.T) {
	uc, orderRepo := newFinalizeUC(finalizeOrderInProgress("driver-owner"))

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   "driver-attacker",
		FinalPrice: 500000,
	})
	if err == nil {
		t.Fatal("expected error for a driver that does not own the order")
	}
	if !strings.Contains(err.Error(), "does not own") {
		t.Fatalf("err = %v, want a 'does not own this order' error", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated by a foreign driver")
	}
	persisted, getErr := orderRepo.GetByID(context.Background(), "order-1")
	if getErr != nil {
		t.Fatalf("GetByID failed: %v", getErr)
	}
	if persisted.Status != orderdomain.StatusInProgress {
		t.Fatalf("status = %q, want still %q", persisted.Status, orderdomain.StatusInProgress)
	}
	if persisted.PriceTotal != 500000 {
		t.Fatalf("price_total = %d, want 500000", persisted.PriceTotal)
	}
}