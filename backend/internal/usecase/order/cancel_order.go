package order

import (
	"context"

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

func (uc *CancelOrderUseCase) Execute(ctx context.Context, orderID string, reason string) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if ord.Status == orderdomain.StatusCancelled {
		return ord, nil
	}
	cancelReason := normalizeCancelReason(reason)

	now := uc.clock.Now()
	previousDriverID := ord.DriverID
	if err := ord.TransitionTo(orderdomain.StatusCancelled, now); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
	}
	if previousDriverID != nil {
		if err := uc.driverRepo.ReleaseOrder(ctx, *previousDriverID, ord.ID, now); err != nil {
			uc.logger.Error("failed to release driver after order cancellation", err, "order_id", ord.ID, "driver_id", *previousDriverID)
			return nil, err
		}
	}
	cancelPayload := map[string]any{
		"status":  ord.Status,
		"reason":  cancelReason,
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
		return nil, err
	}
	return ord, nil
}

func normalizeCancelReason(reason string) string {
	switch reason {
	case "client_cancelled", "driver_cancelled", "driver_offline", "order_cancelled":
		return reason
	default:
		return "order_cancelled"
	}
}
