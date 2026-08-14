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
	uc := NewFinalizeOrderUseCase(orderRepo, &fakePaymentTxRunner{}, fakeCommissionProvider{percent: 15}, 600, publisher, nil, fakeClock{now: now}, fakeLogger{})
	return uc, orderRepo
}

// newFinalizeUCWithTx wires an order with a caller-controlled payment tx runner
// so tests can assert the cash auto-completion settlement contract. The runner
// is bound to the same fake order repo, so a committed status write is visible
// to subsequent GetByID reads (mirroring the database commit).
func newFinalizeUCWithTx(order *orderdomain.Order, paymentTx *fakePaymentTxRunner) (*FinalizeOrderUseCase, *fakeOrderRepository, *fakePaymentTxRunner) {
	orderRepo := &fakeOrderRepository{order: order}
	paymentTx.orderRepo = orderRepo
	publisher := &fakeEventPublisher{}
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	uc := NewFinalizeOrderUseCase(orderRepo, paymentTx, fakeCommissionProvider{percent: 15}, 600, publisher, nil, fakeClock{now: now}, fakeLogger{})
	return uc, orderRepo, paymentTx
}

// TestFinalizeUsesServerPrice guards the normal app flow: the driver app sends
// back the server-computed price and the order completes to awaiting_payment
// (card) with that exact total.
func TestFinalizeUsesServerPrice(t *testing.T) {
	driverID := "driver-1"
	uc, orderRepo := newFinalizeUC(&orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "card",
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

// TestFinalizeCash_AutoCompletesInOneTransaction locks the new cash contract:
// finalizing a cash order settles money (CompleteOrderFinancially with the
// platform commission) AND writes completed inside one WithWebhookTx, then
// publishes the completed event. The plain orderRepo.Update must not be used —
// the status write goes through the settlement tx.
func TestFinalizeCash_AutoCompletesInOneTransaction(t *testing.T) {
	driverID := "driver-1"
	paymentTx := &fakePaymentTxRunner{}
	uc, orderRepo, _ := newFinalizeUCWithTx(&orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "cash",
	}, paymentTx)

	ord, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusCompleted {
		t.Fatalf("status = %q, want %q (cash auto-complete)", ord.Status, orderdomain.StatusCompleted)
	}
	if ord.PriceTotal != 500000 {
		t.Fatalf("price_total = %d, want 500000 (server price)", ord.PriceTotal)
	}
	if paymentTx.txOpenCalls != 1 {
		t.Fatalf("WithWebhookTx calls = %d, want 1 (money+status must be one tx)", paymentTx.txOpenCalls)
	}
	if paymentTx.completeCalls != 1 {
		t.Fatalf("CompleteOrderFinancially (tx) calls = %d, want 1", paymentTx.completeCalls)
	}
	if paymentTx.lastIdempotencyKey != "complete_order:order-1" {
		t.Fatalf("settlement idempotency key = %q, want complete_order:order-1", paymentTx.lastIdempotencyKey)
	}
	if paymentTx.lastCommissionPercent != 15 {
		t.Fatalf("commission percent = %d, want 15", paymentTx.lastCommissionPercent)
	}
	if len(paymentTx.statusUpdates) != 1 || paymentTx.statusUpdates[0] != string(orderdomain.StatusCompleted) {
		t.Fatalf("tx status updates = %+v, want [completed]", paymentTx.statusUpdates)
	}
	if orderRepo.updated {
		t.Fatal("cash finalize used the plain orderRepo.Update; status must go through the settlement tx")
	}
}

// TestFinalizeCash_PublishesCompletedEvent verifies the client/driver are
// notified with a completed event (and the payment-method payload) when a cash
// order auto-completes.
func TestFinalizeCash_PublishesCompletedEvent(t *testing.T) {
	driverID := "driver-1"
	orderRepo := &fakeOrderRepository{order: &orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "cash",
	}}
	publisher := &fakeEventPublisher{}
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	uc := NewFinalizeOrderUseCase(orderRepo, &fakePaymentTxRunner{}, fakeCommissionProvider{percent: 15}, 600, publisher, nil, fakeClock{now: now}, fakeLogger{})

	if _, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	}); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	var completed bool
	for _, ev := range publisher.Events() {
		if ev.Type == orderdomain.EventCompleted && ev.OrderID == "order-1" {
			completed = true
		}
	}
	if !completed {
		t.Fatalf("events = %+v, want one EventCompleted", publisher.Events())
	}
	var awaiting bool
	for _, ev := range publisher.Events() {
		if ev.Type == orderdomain.EventAwaitingPayment {
			awaiting = true
		}
	}
	if awaiting {
		t.Fatal("cash order must not publish awaiting_payment")
	}
}

// TestFinalizeCard_DoesNotOpenCompletionTx verifies the card flow is unchanged:
// after finalize the order is awaiting_payment and no settlement transaction is
// opened (the client pays later).
func TestFinalizeCard_DoesNotOpenCompletionTx(t *testing.T) {
	driverID := "driver-1"
	paymentTx := &fakePaymentTxRunner{}
	uc, _, _ := newFinalizeUCWithTx(&orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "card",
	}, paymentTx)

	ord, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusAwaitingPayment {
		t.Fatalf("status = %q, want %q (card waits for payment)", ord.Status, orderdomain.StatusAwaitingPayment)
	}
	if paymentTx.txOpenCalls != 0 {
		t.Fatalf("WithWebhookTx calls = %d, want 0 for card finalize", paymentTx.txOpenCalls)
	}
	if paymentTx.completeCalls != 0 {
		t.Fatalf("CompleteOrderFinancially calls = %d, want 0 for card finalize", paymentTx.completeCalls)
	}
}

// TestFinalizeCash_SettlementFailureRollsBackEverything verifies the
// all-or-nothing property: when the financial settlement fails inside the
// completion tx, the status write is discarded, the order is NOT moved to
// completed and the caller gets an error.
func TestFinalizeCash_SettlementFailureRollsBackEverything(t *testing.T) {
	driverID := "driver-1"
	paymentTx := &fakePaymentTxRunner{failComplete: true}
	uc, orderRepo, _ := newFinalizeUCWithTx(&orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "cash",
	}, paymentTx)

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	})
	if err == nil {
		t.Fatal("expected error when settlement fails, got nil")
	}
	// Rolled back: the settlement side effects and status write are discarded.
	if paymentTx.completeCalls != 0 {
		t.Fatalf("CompleteOrderFinancially side effects = %d, want 0 (rolled back)", paymentTx.completeCalls)
	}
	if len(paymentTx.statusUpdates) != 0 {
		t.Fatalf("tx status updates = %+v, want none (rolled back)", paymentTx.statusUpdates)
	}
	if orderRepo.updated {
		t.Fatal("order was persisted despite settlement failure")
	}
}

// TestFinalizeCash_StatusWriteFailureRollsBackMoney verifies the other half of
// the all-or-nothing property: if the completed-status write fails, the money
// settlement recorded in the same tx is discarded (no orphaned debt).
func TestFinalizeCash_StatusWriteFailureRollsBackMoney(t *testing.T) {
	driverID := "driver-1"
	paymentTx := &fakePaymentTxRunner{failStatusUpdate: true}
	uc, orderRepo, _ := newFinalizeUCWithTx(&orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "cash",
	}, paymentTx)

	_, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	})
	if err == nil {
		t.Fatal("expected error when status write fails, got nil")
	}
	if paymentTx.completeCalls != 0 {
		t.Fatalf("CompleteOrderFinancially side effects = %d, want 0 (rolled back with status failure)", paymentTx.completeCalls)
	}
	if len(paymentTx.statusUpdates) != 0 {
		t.Fatalf("tx status updates = %+v, want none", paymentTx.statusUpdates)
	}
	if orderRepo.updated {
		t.Fatal("order was persisted despite status-write failure")
	}
}

// TestFinalizeCash_RepeatedFinalizeIsIdempotent verifies a second finalize
// attempt on an already-completed cash order is rejected by the status guard
// before any money logic runs — no double debt.
func TestFinalizeCash_RepeatedFinalizeIsIdempotent(t *testing.T) {
	driverID := "driver-1"
	paymentTx := &fakePaymentTxRunner{}
	uc, _, _ := newFinalizeUCWithTx(&orderdomain.Order{
		ID:            "order-1",
		UserID:        "client-1",
		DriverID:      &driverID,
		Status:        orderdomain.StatusInProgress,
		PriceTotal:    500000,
		PaymentMethod: "cash",
	}, paymentTx)

	if _, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	}); err != nil {
		t.Fatalf("first finalize: %v", err)
	}

	if _, err := uc.Execute(context.Background(), FinalizeOrderInput{
		OrderID:    "order-1",
		DriverID:   driverID,
		FinalPrice: 500000,
	}); !errors.Is(err, orderdomain.ErrInvalidTransition) {
		t.Fatalf("second finalize err = %v, want ErrInvalidTransition", err)
	}
	if paymentTx.completeCalls != 1 {
		t.Fatalf("CompleteOrderFinancially calls = %d, want 1 (no double settlement)", paymentTx.completeCalls)
	}
	if len(paymentTx.statusUpdates) != 1 {
		t.Fatalf("tx status updates = %+v, want exactly one completed write", paymentTx.statusUpdates)
	}
}
