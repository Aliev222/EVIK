package order

import (
	"context"

	orderdomain "evik/backend/internal/domain/order"
)

type CancelOrderUseCase struct {
	orderRepo      orderdomain.Repository
	eventPublisher EventPublisher
	clock          Clock
	logger         Logger
}

func NewCancelOrderUseCase(orderRepo orderdomain.Repository, eventPublisher EventPublisher, clock Clock, logger Logger) *CancelOrderUseCase {
	return &CancelOrderUseCase{orderRepo: orderRepo, eventPublisher: eventPublisher, clock: clock, logger: logger}
}

func (uc *CancelOrderUseCase) Execute(ctx context.Context, orderID string) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if err := ord.TransitionTo(orderdomain.StatusCancelled, uc.clock.Now()); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventCancelled,
		OrderID: ord.ID,
		Payload: map[string]any{"status": ord.Status},
	}); err != nil {
		uc.logger.Error("failed to publish cancelled status", err, "order_id", ord.ID)
		return nil, err
	}
	return ord, nil
}
