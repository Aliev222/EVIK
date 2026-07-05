package order

import (
	"context"
	"fmt"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

type FinalizeOrderUseCase struct {
	orderRepo      orderdomain.Repository
	eventPublisher EventPublisher
	pushSender     PushSender
	clock          Clock
	logger         Logger
}

type FinalizeOrderInput struct {
	OrderID    string
	DriverID   string
	FinalPrice int64
}

func NewFinalizeOrderUseCase(
	orderRepo orderdomain.Repository,
	eventPublisher EventPublisher,
	pushSender PushSender,
	clock Clock,
	logger Logger,
) *FinalizeOrderUseCase {
	return &FinalizeOrderUseCase{
		orderRepo:      orderRepo,
		eventPublisher: eventPublisher,
		pushSender:     pushSender,
		clock:          clock,
		logger:         logger,
	}
}

func (uc *FinalizeOrderUseCase) Execute(ctx context.Context, input FinalizeOrderInput) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, input.OrderID)
	if err != nil {
		return nil, err
	}
	if ord.DriverID == nil || *ord.DriverID != input.DriverID {
		return nil, fmt.Errorf("driver does not own this order")
	}
	if ord.Status != orderdomain.StatusInProgress {
		return nil, orderdomain.ErrInvalidTransition
	}
	if input.FinalPrice <= 0 {
		return nil, fmt.Errorf("final price must be positive")
	}

	now := uc.clock.Now()
	ord.PriceTotal = input.FinalPrice
	if err := ord.TransitionTo(orderdomain.StatusAwaitingPayment, now); err != nil {
		return nil, err
	}

	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
	}

	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventAwaitingPayment,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status":      ord.Status,
			"price_total": ord.PriceTotal,
			"driver_id":   *ord.DriverID,
			"user_id":     ord.UserID,
		},
	}); err != nil {
		uc.logger.Error("failed to publish awaiting_payment event", err, "order_id", ord.ID)
	}

	uc.notifyClientAwaitingPayment(ctx, ord)

	uc.logger.Info("order finalized by driver",
		"order_id", ord.ID,
		"driver_id", input.DriverID,
		"final_price", input.FinalPrice)
	return ord, nil
}

func (uc *FinalizeOrderUseCase) notifyClientAwaitingPayment(parent context.Context, ord *orderdomain.Order) {
	if uc.pushSender == nil {
		return
	}
	go func() {
		pushCtx, cancel := context.WithTimeout(context.WithoutCancel(parent), 5*time.Second)
		defer cancel()
		title := "Заказ ожидает оплаты"
		body := fmt.Sprintf("Сумма к оплате: %.2f ₽", float64(ord.PriceTotal)/100)
		data := map[string]string{
			"type":     "awaiting_payment",
			"order_id": ord.ID,
			"price":    fmt.Sprintf("%d", ord.PriceTotal),
		}
		if err := uc.pushSender.SendToUser(pushCtx, ord.UserID, "client", title, body, data); err != nil {
			uc.logger.Error("failed to send awaiting_payment push", err, "order_id", ord.ID, "user_id", ord.UserID)
		}
	}()
}
