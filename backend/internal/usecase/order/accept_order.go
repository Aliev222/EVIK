package order

import (
	"context"

	orderdomain "evik/backend/internal/domain/order"
)

type AcceptOrderUseCase struct {
	orderRepo      orderdomain.Repository
	eventPublisher EventPublisher
	clock          Clock
	logger         Logger
}

func NewAcceptOrderUseCase(
	orderRepo orderdomain.Repository,
	eventPublisher EventPublisher,
	clock Clock,
	logger Logger,
) *AcceptOrderUseCase {
	return &AcceptOrderUseCase{
		orderRepo:      orderRepo,
		eventPublisher: eventPublisher,
		clock:          clock,
		logger:         logger,
	}
}

func (uc *AcceptOrderUseCase) Execute(ctx context.Context, orderID string, driverID string) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}

	now := uc.clock.Now()
	if err := ord.AssignDriver(driverID, now); err != nil {
		return nil, err
	}
	if err := ord.TransitionTo(orderdomain.StatusAccepted, now); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventAccepted,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status":    ord.Status,
			"driver_id": driverID,
		},
	}); err != nil {
		uc.logger.Error("failed to publish accepted status", err, "order_id", ord.ID)
		return nil, err
	}

	return ord, nil
}
