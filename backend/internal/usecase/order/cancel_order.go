package order

import (
	"context"
	"errors"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

type CancelOrderUseCase struct {
	orderRepo      orderdomain.Repository
	driverRepo     DriverOrderRepository
	eventPublisher EventPublisher
	clock          Clock
	logger         Logger
}

func NewCancelOrderUseCase(orderRepo orderdomain.Repository, driverRepo DriverOrderRepository, eventPublisher EventPublisher, clock Clock, logger Logger) *CancelOrderUseCase {
	return &CancelOrderUseCase{orderRepo: orderRepo, driverRepo: driverRepo, eventPublisher: eventPublisher, clock: clock, logger: logger}
}

// Execute cancels an order atomically and releases the assigned driver.
//
// The status flip itself uses a single conditional UPDATE...RETURNING (no
// read-modify-write), so the cancel-vs-accept race can never overwrite a fresh
// driver assignment with a stale snapshot: the RETURNING projection carries the
// CURRENT driver_id at statement time, and that exact driver is released
// afterwards (BUG-CANCEL-RACE-DRIVER). The order row is persisted before the
// driver release so a release failure is recoverable: a repeated cancel of an
// already-cancelled order (CancelledAt set) re-attempts the release and the
// cancelled-event publication instead of silently short-circuiting
// (BUG-CANCEL-RELEASE / BUG-CANCEL-EVENT).
func (uc *CancelOrderUseCase) Execute(ctx context.Context, orderID string, reason string) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if ord.Status == orderdomain.StatusCompleted {
		return nil, orderdomain.ErrInvalidTransition
	}
	cancelReason := normalizeCancelReason(reason)
	now := uc.clock.Now()

	// Idempotent repeat of an already-cancelled order. A cancelled order that
	// was actually terminated (has a cancel timestamp) may still have a driver
	// attached if the previous cancel failed mid-way: re-attempt the release
	// and the event, but never re-persist or double-fire side effects.
	if ord.Status == orderdomain.StatusCancelled {
		return uc.handleRepeatCancel(ctx, ord, cancelReason, now)
	}

	updated, err := uc.orderRepo.CancelOrder(ctx, orderID, cancelReason, now)
	if err != nil {
		if errors.Is(err, orderdomain.ErrOrderNotFound) {
			// A concurrent writer already terminated the order (another cancel
			// or a completion won the race). Classify and fall into the
			// idempotent/retry path instead of failing the caller blindly.
			reloaded, getErr := uc.orderRepo.GetByID(ctx, orderID)
			if getErr != nil {
				return nil, getErr
			}
			if reloaded.Status == orderdomain.StatusCompleted {
				return nil, orderdomain.ErrInvalidTransition
			}
			return uc.handleRepeatCancel(ctx, reloaded, cancelReason, now)
		}
		return nil, err
	}
	ord = updated

	if ord.DriverID != nil {
		if err := uc.driverRepo.ReleaseOrder(ctx, *ord.DriverID, ord.ID, now); err != nil {
			uc.logger.Error("failed to release driver after order cancellation", err, "order_id", ord.ID, "driver_id", *ord.DriverID)
			return nil, err
		}
	}

	if err := uc.publishCancelled(ctx, ord, cancelReason); err != nil {
		return nil, err
	}
	return ord, nil
}

// handleRepeatCancel covers a repeated cancellation. Orders seeded into
// 'cancelled' without a cancel timestamp are treated as a pure no-op (no
// release, no event). Orders carrying a cancel timestamp were terminated by a
// prior cancel that may have failed after the DB write, so the driver release
// and the cancelled event are safely re-attempted here.
func (uc *CancelOrderUseCase) handleRepeatCancel(ctx context.Context, ord *orderdomain.Order, cancelReason string, now time.Time) (*orderdomain.Order, error) {
	if ord.CancelledAt == nil {
		return ord, nil
	}
	if ord.DriverID != nil {
		if err := uc.driverRepo.ReleaseOrder(ctx, *ord.DriverID, ord.ID, now); err != nil {
			uc.logger.Error("failed to release driver on repeated cancel", err, "order_id", ord.ID, "driver_id", *ord.DriverID)
			return nil, err
		}
	}
	if err := uc.publishCancelled(ctx, ord, cancelReason); err != nil {
		return nil, err
	}
	return ord, nil
}

// publishCancelled fires the cancelled event with the order payload.
func (uc *CancelOrderUseCase) publishCancelled(ctx context.Context, ord *orderdomain.Order, reason string) error {
	cancelPayload := map[string]any{
		"status":  orderdomain.StatusCancelled,
		"reason":  reason,
		"user_id": ord.UserID,
	}
	if ord.DriverID != nil {
		cancelPayload["driver_id"] = *ord.DriverID
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventCancelled,
		OrderID: ord.ID,
		Payload: cancelPayload,
	}); err != nil {
		uc.logger.Error("failed to publish cancelled status", err, "order_id", ord.ID)
		return err
	}
	return nil
}

func normalizeCancelReason(reason string) string {
	switch reason {
	case "client_cancelled", "driver_cancelled", "driver_offline", "order_cancelled":
		return reason
	default:
		return "order_cancelled"
	}
}