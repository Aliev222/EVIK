package order

import (
	"context"

	orderdomain "evik/backend/internal/domain/order"
)

type UpdateStatusUseCase struct {
	orderRepo      orderdomain.Repository
	driverRepo     DriverOrderRepository
	eventPublisher EventPublisher
	clock          Clock
}

func NewUpdateStatusUseCase(orderRepo orderdomain.Repository, driverRepo DriverOrderRepository, eventPublisher EventPublisher, clock Clock) *UpdateStatusUseCase {
	return &UpdateStatusUseCase{orderRepo: orderRepo, driverRepo: driverRepo, eventPublisher: eventPublisher, clock: clock}
}

func (uc *UpdateStatusUseCase) Execute(ctx context.Context, orderID string, next orderdomain.Status) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if ord.Status == next {
		return ord, nil
	}

	now := uc.clock.Now()
	previousDriverID := ord.DriverID
	if err := ord.TransitionTo(next, now); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
	}
	if previousDriverID != nil && releasesDriver(next) {
		if err := uc.driverRepo.ReleaseOrder(ctx, *previousDriverID, ord.ID, now); err != nil {
			return nil, err
		}
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventTypeFromStatus(ord.Status),
		OrderID: ord.ID,
		Payload: map[string]any{"status": ord.Status},
	}); err != nil {
		return nil, err
	}
	return ord, nil
}

func releasesDriver(status orderdomain.Status) bool {
	switch status {
	case orderdomain.StatusCompleted, orderdomain.StatusCancelled, orderdomain.StatusNoDriverFound:
		return true
	default:
		return false
	}
}
