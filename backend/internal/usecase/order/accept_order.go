package order

import (
	"context"
	"errors"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
)

type DriverOrderRepository interface {
	AssignOrder(ctx context.Context, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error)
	ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
}

type AcceptOrderUseCase struct {
	orderRepo      orderdomain.Repository
	driverRepo     DriverOrderRepository
	eventPublisher EventPublisher
	clock          Clock
	logger         Logger
}

func NewAcceptOrderUseCase(
	orderRepo orderdomain.Repository,
	driverRepo DriverOrderRepository,
	eventPublisher EventPublisher,
	clock Clock,
	logger Logger,
) *AcceptOrderUseCase {
	return &AcceptOrderUseCase{
		orderRepo:      orderRepo,
		driverRepo:     driverRepo,
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

	if isSameDriverActiveOrder(ord, driverID) {
		return ord, nil
	}

	now := uc.clock.Now()
	if err := ord.TransitionTo(orderdomain.StatusAccepted, now); err != nil {
		return nil, err
	}
	if err := ord.AssignDriver(driverID, now); err != nil {
		return nil, err
	}
	driverAssigned := false
	if _, err := uc.driverRepo.AssignOrder(ctx, driverID, orderID, now); err != nil {
		if errors.Is(err, driverdomain.ErrDriverUnavailable) {
			reuseCurrentOrder, recovered, recoverErr := uc.tryRecoverDriverAvailability(ctx, driverID, orderID, now)
			if recoverErr != nil {
				return nil, recoverErr
			}
			switch {
			case reuseCurrentOrder:
				driverAssigned = true
			case recovered:
				if _, retryErr := uc.driverRepo.AssignOrder(ctx, driverID, orderID, now); retryErr != nil {
					return nil, retryErr
				}
				driverAssigned = true
			default:
				return nil, err
			}
		} else {
			return nil, err
		}
	} else {
		driverAssigned = true
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		if driverAssigned {
			if releaseErr := uc.driverRepo.ReleaseOrder(ctx, driverID, orderID, now); releaseErr != nil {
				uc.logger.Error("failed to release driver after order update failure", releaseErr, "order_id", ord.ID, "driver_id", driverID)
			}
		}
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

func (uc *AcceptOrderUseCase) tryRecoverDriverAvailability(
	ctx context.Context,
	driverID string,
	targetOrderID string,
	now time.Time,
) (reuseCurrentOrder bool, recovered bool, err error) {
	drv, err := uc.driverRepo.GetByID(ctx, driverID)
	if err != nil {
		if errors.Is(err, driverdomain.ErrDriverNotFound) {
			return false, false, nil
		}
		return false, false, err
	}
	if drv.CurrentOrderID == nil {
		return false, false, nil
	}

	currentOrderID := *drv.CurrentOrderID
	if currentOrderID == targetOrderID {
		return true, false, nil
	}

	activeOrder, err := uc.orderRepo.GetByID(ctx, currentOrderID)
	if err != nil {
		if errors.Is(err, orderdomain.ErrOrderNotFound) {
			if releaseErr := uc.driverRepo.ReleaseOrder(ctx, driverID, currentOrderID, now); releaseErr != nil {
				uc.logger.Error("failed to release missing stale order from driver", releaseErr, "driver_id", driverID, "order_id", currentOrderID)
				return false, false, releaseErr
			}
			return false, true, nil
		}
		return false, false, err
	}

	if !isTerminalOrderStatus(activeOrder.Status) {
		return false, false, nil
	}

	if releaseErr := uc.driverRepo.ReleaseOrder(ctx, driverID, currentOrderID, now); releaseErr != nil {
		uc.logger.Error("failed to release terminal stale order from driver", releaseErr, "driver_id", driverID, "order_id", currentOrderID)
		return false, false, releaseErr
	}
	return false, true, nil
}

func isTerminalOrderStatus(status orderdomain.Status) bool {
	switch status {
	case orderdomain.StatusCompleted, orderdomain.StatusCancelled, orderdomain.StatusNoDriverFound:
		return true
	default:
		return false
	}
}

func isSameDriverActiveOrder(ord *orderdomain.Order, driverID string) bool {
	if ord.DriverID == nil || *ord.DriverID != driverID {
		return false
	}
	switch ord.Status {
	case orderdomain.StatusAccepted, orderdomain.StatusArrived, orderdomain.StatusInProgress:
		return true
	default:
		return false
	}
}
