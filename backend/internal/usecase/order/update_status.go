package order

import (
	"context"
	"fmt"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

type UpdateStatusUseCase struct {
	orderRepo      orderdomain.Repository
	driverRepo     DriverOrderRepository
	eventPublisher EventPublisher
	financeService interface {
		CompleteOrderFinancially(ctx context.Context, orderID string) error
	}
	pushSender PushSender
	clock      Clock
	logger     Logger
}

func NewUpdateStatusUseCase(orderRepo orderdomain.Repository, driverRepo DriverOrderRepository, eventPublisher EventPublisher, financeService interface {
	CompleteOrderFinancially(ctx context.Context, orderID string) error
}, pushSender PushSender, clock Clock, logger Logger) *UpdateStatusUseCase {
	return &UpdateStatusUseCase{orderRepo: orderRepo, driverRepo: driverRepo, eventPublisher: eventPublisher, financeService: financeService, pushSender: pushSender, clock: clock, logger: logger}
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

	// Finance must succeed before the status is persisted.
	// If it fails, the order remains in its current DB state and the driver stays busy.
	if next == orderdomain.StatusCompleted && uc.financeService != nil {
		if err := uc.financeService.CompleteOrderFinancially(ctx, ord.ID); err != nil {
			return nil, fmt.Errorf("Не удалось завершить оплату: %w", err)
		}
	}

	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		if next == orderdomain.StatusCompleted {
			// Money moved but status didn't — recoverable by admin, log at CRITICAL.
			uc.logger.Error("CRITICAL: financial completion succeeded but order status update failed — manual intervention required", err, "order_id", ord.ID)
		}
		return nil, err
	}
	if previousDriverID != nil && releasesDriver(next) {
		if err := uc.driverRepo.ReleaseOrder(ctx, *previousDriverID, ord.ID, now); err != nil {
			return nil, err
		}
	}
	evPayload := map[string]any{
		"status":  ord.Status,
		"user_id": ord.UserID,
	}
	if ord.DriverID != nil {
		evPayload["driver_id"] = *ord.DriverID
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventTypeFromStatus(ord.Status),
		OrderID: ord.ID,
		Payload: evPayload,
	}); err != nil {
		return nil, err
	}

	uc.notifyClientStatusChange(ctx, ord)

	return ord, nil
}

// notifyClientStatusChange fires a push at the order's client for the two
// transitions the customer cares about: the driver arriving at pickup and
// the order completing. All other transitions stay WebSocket-only because
// the client app is typically in foreground for them. Errors are logged
// and swallowed so push failures never roll back a successful transition.
func (uc *UpdateStatusUseCase) notifyClientStatusChange(parent context.Context, ord *orderdomain.Order) {
	if uc.pushSender == nil {
		return
	}
	var title, body string
	switch ord.Status {
	case orderdomain.StatusArrived:
		title = "Эвакуатор прибыл"
		body = "Водитель ожидает вас в точке подачи"
	case orderdomain.StatusCompleted:
		title = "Заказ завершён"
		body = "Спасибо, что воспользовались Tow Truck"
	default:
		return
	}

	pushCtx, cancel := context.WithTimeout(context.WithoutCancel(parent), 5*time.Second)
	defer cancel()

	data := map[string]string{
		"type":     "order_status",
		"order_id": ord.ID,
		"status":   string(ord.Status),
	}
	if err := uc.pushSender.SendToUser(pushCtx, ord.UserID, "client", title, body, data); err != nil {
		uc.logger.Error("failed to send status push to client", err, "order_id", ord.ID, "status", ord.Status, "user_id", ord.UserID)
	}
}

func releasesDriver(status orderdomain.Status) bool {
	switch status {
	case orderdomain.StatusCompleted, orderdomain.StatusCancelled, orderdomain.StatusNoDriverFound:
		return true
	default:
		return false
	}
}
