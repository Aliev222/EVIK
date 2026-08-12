package order

import (
	"context"
	"errors"
	"testing"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
)

// Adversarial coverage for CancelOrderUseCase: cancellation at every stage of
// the lifecycle, driver release semantics, idempotency of repeated cancels,
// reason normalization and rejection of completed orders.

// cancelDriverRepo is a minimal driver-order fake that records release calls
// and can be configured to fail on ReleaseOrder.
type cancelDriverRepo struct {
	releaseErr    error
	releasedOrder []string
	releasedID    []string
}

func (r *cancelDriverRepo) AssignOrder(_ context.Context, _, _ string, _ time.Time) (*driverdomain.Driver, error) {
	return nil, nil
}

func (r *cancelDriverRepo) ReleaseOrder(_ context.Context, driverID string, orderID string, _ time.Time) error {
	if r.releaseErr != nil {
		return r.releaseErr
	}
	r.releasedID = append(r.releasedID, driverID)
	r.releasedOrder = append(r.releasedOrder, orderID)
	return nil
}

func (r *cancelDriverRepo) GetByID(_ context.Context, _ string) (*driverdomain.Driver, error) {
	return nil, nil
}

// cancelOrder is a helper that constructs an order in the given status,
// optionally with an assigned driver, and returns the usecase wired to the
// fake repositories.
func cancelOrder(status orderdomain.Status, driverID *string) (*fakeOrderRepository, *cancelDriverRepo, *fakeEventPublisher, *CancelOrderUseCase) {
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:         "order-1",
			UserID:     "client-1",
			DriverID:   driverID,
			Status:     status,
			PriceTotal: 500000,
		},
	}
	driverRepo := &cancelDriverRepo{}
	publisher := &fakeEventPublisher{}
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	uc := NewCancelOrderUseCase(orderRepo, driverRepo, publisher, fakeClock{now: now}, fakeLogger{})
	return orderRepo, driverRepo, publisher, uc
}

var cancellableStages = []orderdomain.Status{
	orderdomain.StatusCreated,
	orderdomain.StatusSearching,
	orderdomain.StatusAccepted,
	orderdomain.StatusArrived,
	orderdomain.StatusInProgress,
	orderdomain.StatusAwaitingPayment,
}

// TestCancelOrder_AllowedAtEveryStage verifies the order can be cancelled
// from each pre-terminal stage of the lifecycle: the transition succeeds, the
// order lands in cancelled with CancelledAt stamped, the reason is persisted
// and a cancelled event is published.
func TestCancelOrder_AllowedAtEveryStage(t *testing.T) {
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	for _, status := range cancellableStages {
		t.Run(string(status), func(t *testing.T) {
			orderRepo, _, publisher, uc := cancelOrder(status, nil)

			ord, err := uc.Execute(context.Background(), "order-1", "client_cancelled")
			if err != nil {
				t.Fatalf("Execute: %v", err)
			}
			if ord.Status != orderdomain.StatusCancelled {
				t.Fatalf("status = %q, want cancelled", ord.Status)
			}
			if ord.CancelledAt == nil || !ord.CancelledAt.Equal(now) {
				t.Fatalf("CancelledAt = %v, want %v", ord.CancelledAt, now)
			}
			if ord.CancelReason != "client_cancelled" {
				t.Fatalf("CancelReason = %q, want client_cancelled", ord.CancelReason)
			}
			if !orderRepo.updated {
				t.Fatal("order was not persisted after cancellation")
			}
			var cancelledEvent bool
			for _, ev := range publisher.Events() {
				if ev.Type == orderdomain.EventCancelled && ev.OrderID == "order-1" {
					cancelledEvent = true
				}
			}
			if !cancelledEvent {
				t.Fatal("expected EventCancelled to be published")
			}
		})
	}
}

// TestCancelOrder_WithAssignedDriver_ReleasesDriver verifies the release
// contract: when the cancelled order had a driver, that exact driver/order
// pair is released through the driver repository.
func TestCancelOrder_WithAssignedDriver_ReleasesDriver(t *testing.T) {
	driverID := "driver-7"
	_, driverRepo, _, uc := cancelOrder(orderdomain.StatusAccepted, &driverID)

	ord, err := uc.Execute(context.Background(), "order-1", "driver_cancelled")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
	if len(driverRepo.releasedID) != 1 || driverRepo.releasedID[0] != driverID {
		t.Fatalf("released drivers = %v, want [%s]", driverRepo.releasedID, driverID)
	}
	if len(driverRepo.releasedOrder) != 1 || driverRepo.releasedOrder[0] != "order-1" {
		t.Fatalf("released orders = %v, want [order-1]", driverRepo.releasedOrder)
	}
}

// TestCancelOrder_WithoutDriver_DoesNotTouchDriverRepo locks the contract
// that a driver-less cancellation never dereferences the driver repository —
// even when it is nil. This is the adversarial guard against a nil-pointer
// panic on orders that never had a driver assigned.
func TestCancelOrder_WithoutDriver_DoesNotTouchDriverRepo(t *testing.T) {
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:         "order-1",
			UserID:     "client-1",
			Status:     orderdomain.StatusSearching,
			PriceTotal: 500000,
		},
	}
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	uc := NewCancelOrderUseCase(orderRepo, nil, &fakeEventPublisher{}, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", "")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
}

// TestCancelOrder_AlreadyCancelled_IsIdempotent verifies a repeated
// cancellation of an already-cancelled order: no error, the current order is
// returned unchanged, nothing is re-persisted, no driver release is retried
// and no duplicate event fires.
func TestCancelOrder_AlreadyCancelled_IsIdempotent(t *testing.T) {
	driverID := "driver-7"
	orderRepo, driverRepo, publisher, uc := cancelOrder(orderdomain.StatusCancelled, &driverID)

	ord, err := uc.Execute(context.Background(), "order-1", "client_cancelled")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
	if orderRepo.updated {
		t.Fatal("already-cancelled order was re-persisted")
	}
	if len(driverRepo.releasedID) != 0 || len(driverRepo.releasedOrder) != 0 {
		t.Fatalf("driver was released again: released = %v / %v", driverRepo.releasedID, driverRepo.releasedOrder)
	}
	if len(publisher.Events()) != 0 {
		t.Fatalf("events = %+v, want none for idempotent cancel", publisher.Events())
	}
}

// TestCancelOrder_NormalizeCancelReason verifies the reason whitelist:
// known reasons pass through verbatim, everything else (including empty and
// arbitrary strings) collapses to the default order_cancelled.
func TestCancelOrder_NormalizeCancelReason(t *testing.T) {
	for _, known := range []string{"client_cancelled", "driver_cancelled", "driver_offline", "order_cancelled"} {
		if got := normalizeCancelReason(known); got != known {
			t.Errorf("normalizeCancelReason(%q) = %q, want %q", known, got, known)
		}
	}
	for _, unknown := range []string{"", "kebab", "client changed mind", "COMPLETED_BY_ACCIDENT"} {
		if got := normalizeCancelReason(unknown); got != "order_cancelled" {
			t.Errorf("normalizeCancelReason(%q) = %q, want order_cancelled", unknown, got)
		}
	}
}

// TestCancelOrder_CompletedOrder_Rejected verifies cancellation of a
// completed order is rejected by the state machine: ErrInvalidTransition,
// nothing persisted, the driver untouched and no event published.
func TestCancelOrder_CompletedOrder_Rejected(t *testing.T) {
	driverID := "driver-7"
	orderRepo, driverRepo, publisher, uc := cancelOrder(orderdomain.StatusCompleted, &driverID)

	_, err := uc.Execute(context.Background(), "order-1", "client_cancelled")
	if !errors.Is(err, orderdomain.ErrInvalidTransition) {
		t.Fatalf("Execute: err = %v, want ErrInvalidTransition", err)
	}
	if orderRepo.updated {
		t.Fatal("completed order was persisted on rejected cancel")
	}
	if len(driverRepo.releasedID) != 0 || len(driverRepo.releasedOrder) != 0 {
		t.Fatalf("driver of completed order was released: %v / %v", driverRepo.releasedID, driverRepo.releasedOrder)
	}
	if len(publisher.Events()) != 0 {
		t.Fatalf("events = %+v, want none", publisher.Events())
	}
}

// TestCancelOrder_NoDriverFound_Rejected documents the current state machine
// gap around the probing dead-end: an order in no_driver_found can neither be
// cancelled nor transition anywhere else, so a client-side cancel request
// fails with ErrInvalidTransition and the order stays frozen in the dead-end.
// Per the product contract «отмена возможна на всех этапах до completed» the
// cancellation of a no_driver_found order must succeed and release the
// (possibly) assigned driver. See bug id BUG-CANCEL-NODRIVER in the report.
func TestCancelOrder_NoDriverFound_Rejected(t *testing.T) {
	driverID := "driver-7"
	orderRepo, driverRepo, publisher, uc := cancelOrder(orderdomain.StatusNoDriverFound, &driverID)

	ord, err := uc.Execute(context.Background(), "order-1", "client_cancelled")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
	if !orderRepo.updated {
		t.Fatal("order was not persisted after cancellation")
	}
	if len(driverRepo.releasedID) != 1 {
		t.Fatalf("driver was not released, released = %v", driverRepo.releasedID)
	}
	if evs := publisher.Events(); len(evs) != 1 || evs[0].Type != orderdomain.EventCancelled {
		t.Fatalf("events = %+v, want one cancelled event", evs)
	}
}

// TestCancelOrder_RetryAfterReleaseFailure_MustStillReleaseDriver documents
// the release-failure retry hole: when the first cancel persists the
// cancellation but ReleaseOrder fails, the caller gets an error. A retry then
// hits the early `StatusCancelled` return and exits without ever releasing
// the driver — the driver stays busy on a cancelled order forever. See bug id
// BUG-CANCEL-RELEASE in the report.
func TestCancelOrder_RetryAfterReleaseFailure_MustStillReleaseDriver(t *testing.T) {
	driverID := "driver-7"
	orderRepo, driverRepo, _, uc := cancelOrder(orderdomain.StatusAccepted, &driverID)
	driverRepo.releaseErr = errors.New("driver repo transient outage")

	if _, err := uc.Execute(context.Background(), "order-1", "client_cancelled"); err == nil {
		t.Fatal("first cancel: expected error when ReleaseOrder fails")
	}
	// The cancellation is already persisted, but the driver is still busy.
	persisted, _ := orderRepo.GetByID(context.Background(), "order-1")
	if persisted.Status != orderdomain.StatusCancelled {
		t.Fatalf("persisted status = %q, want cancelled", persisted.Status)
	}

	driverRepo.releaseErr = nil
	if _, err := uc.Execute(context.Background(), "order-1", "client_cancelled"); err != nil {
		t.Fatalf("retry cancel: %v", err)
	}
	if len(driverRepo.releasedID) != 1 || driverRepo.releasedID[0] != driverID {
		t.Fatalf("driver was never released on retry, released = %v", driverRepo.releasedID)
	}
}

// TestCancelOrder_PublishFailure_Retry_NoDuplicateEvent documents the same
// short-circuit around event publishing: when the cancelled event publish
// fails after the DB write, a retry returns success but the event is silently
// never published again. See bug id BUG-CANCEL-EVENT in the report.
func TestCancelOrder_PublishFailure_Retry_NoDuplicateEvent(t *testing.T) {
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:         "order-1",
			UserID:     "client-1",
			Status:     orderdomain.StatusSearching,
			PriceTotal: 500000,
		},
	}
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	publisher := &failingEventPublisher{fail: true}
	uc := NewCancelOrderUseCase(orderRepo, &cancelDriverRepo{}, publisher, fakeClock{now: now}, fakeLogger{})

	if _, err := uc.Execute(context.Background(), "order-1", "client_cancelled"); err == nil {
		t.Fatal("first cancel: expected error when publish fails")
	}
	publisher.fail = false
	ord, err := uc.Execute(context.Background(), "order-1", "client_cancelled")
	if err != nil {
		t.Fatalf("retry cancel: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
	if len(publisher.events) != 1 || publisher.events[0].Type != orderdomain.EventCancelled {
		t.Fatalf("events = %+v, want exactly one cancelled event on retry", publisher.events)
	}
}

type failingEventPublisher struct {
	fail   bool
	events []orderdomain.Event
}

func (p *failingEventPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	if p.fail {
		return errors.New("publisher down")
	}
	p.events = append(p.events, event)
	return nil
}
