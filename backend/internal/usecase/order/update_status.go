package order

import (
	"context"

	orderdomain "evik/backend/internal/domain/order"
)

type UpdateStatusUseCase struct {
	orderRepo      orderdomain.Repository
	eventPublisher EventPublisher
	clock          Clock
}

func NewUpdateStatusUseCase(orderRepo orderdomain.Repository, eventPublisher EventPublisher, clock Clock) *UpdateStatusUseCase {
	return &UpdateStatusUseCase{orderRepo: orderRepo, eventPublisher: eventPublisher, clock: clock}
}

func (uc *UpdateStatusUseCase) Execute(ctx context.Context, orderID string, next orderdomain.Status) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if err := ord.TransitionTo(next, uc.clock.Now()); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
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
