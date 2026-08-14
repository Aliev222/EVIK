package order

import (
	"context"
	"errors"
	"fmt"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
)

// finalPriceToleranceKopecks is the maximum allowed deviation between the
// caller-supplied final_price and the server-computed order price. The server
// is authoritative for the completion price: the caller's number is validated
// against this tolerance and is never written to the order. A tiny tolerance
// absorbs client-side display rounding while still rejecting any attempt to
// move the price up or down.
const finalPriceToleranceKopecks int64 = 100

// ErrFinalPriceMismatch is returned when the caller-supplied final_price
// deviates from the server-computed order price by more than the tolerance.
var ErrFinalPriceMismatch = errors.New("final_price does not match the server-computed order price")

// PaymentTxRunner runs a callback inside a single database transaction. The
// callback's WebhookTx operations (financial settlement + order status write)
// commit together or roll back together, making the cash auto-completion
// atomic.
type PaymentTxRunner interface {
	WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error
}

// CommissionPercentProvider returns the platform commission percentage
// (default 15) used to compute the cash-order debt. Implemented by the finance
// use case so the fee logic stays in one place.
type CommissionPercentProvider interface {
	CommissionPercent(ctx context.Context) int
}

type FinalizeOrderUseCase struct {
	orderRepo          orderdomain.Repository
	paymentTx          PaymentTxRunner
	commissionProvider CommissionPercentProvider
	holdSeconds        int
	eventPublisher     EventPublisher
	pushSender         PushSender
	clock              Clock
	logger             Logger
}

type FinalizeOrderInput struct {
	OrderID    string
	DriverID   string
	FinalPrice int64
}

func NewFinalizeOrderUseCase(
	orderRepo orderdomain.Repository,
	paymentTx PaymentTxRunner,
	commissionProvider CommissionPercentProvider,
	holdSeconds int,
	eventPublisher EventPublisher,
	pushSender PushSender,
	clock Clock,
	logger Logger,
) *FinalizeOrderUseCase {
	return &FinalizeOrderUseCase{
		orderRepo:          orderRepo,
		paymentTx:          paymentTx,
		commissionProvider: commissionProvider,
		holdSeconds:        holdSeconds,
		eventPublisher:     eventPublisher,
		pushSender:         pushSender,
		clock:              clock,
		logger:             logger,
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

	// The server is the source of truth for the completion price. PriceTotal
	// was computed by the server at order creation and, for cross-city trips,
	// already includes the 50% surcharge applied at accept time. The driver app
	// echoes that number back in final_price; it is validated below against the
	// server price but is never written to the order.
	serverPrice := ord.PriceTotal
	if serverPrice <= 0 {
		uc.logger.Error("cannot finalize order without a server-computed price", nil,
			"order_id", ord.ID, "driver_id", input.DriverID, "price_total", serverPrice)
		return nil, orderdomain.ErrValidationFailed
	}
	if input.FinalPrice <= 0 {
		return nil, fmt.Errorf("final price must be positive")
	}
	if diff := kopecksDiff(serverPrice, input.FinalPrice); diff > finalPriceToleranceKopecks {
		uc.logger.Info("finalize rejected: caller price deviates from server price",
			"order_id", ord.ID, "driver_id", input.DriverID,
			"server_price", serverPrice, "caller_price", input.FinalPrice, "diff_kopecks", diff)
		return nil, ErrFinalPriceMismatch
	}

	// TODO(server-authoritative-price): a future feature will compute a
	// per-extra-km surcharge for the actually driven distance (server measures
	// the real route vs the estimate and adds per-km from the tariff). That
	// adjustment plugs in here, on top of serverPrice, and requires
	// driven-distance measurement — out of scope for now.

	now := uc.clock.Now()
	ord.PriceTotal = serverPrice

	// Cash orders settle immediately at finalize: the commission debt is
	// recorded and the order advances straight to completed in one
	// transaction, so the client does not need to confirm anything. Card
	// orders keep the awaiting_payment step: the client pays and the order
	// completes either via the payment webhook or ConfirmOrderPayment.
	paymentMethod := ord.PaymentMethod
	if paymentMethod == "" {
		paymentMethod = "cash"
	}

	if paymentMethod == "cash" {
		return uc.finalizeCash(ctx, ord, now)
	}

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
		"final_price", input.FinalPrice,
		"server_price", serverPrice)
	return ord, nil
}

// finalizeCash settles a cash order at driver finalize. Money settlement
// (commission debt, driver release, financial close) and the completed-status
// write run inside a single WithWebhookTx transaction: a failure rolls both
// back and the order stays in_progress. The settlement itself is idempotent
// (wallet_transactions.idempotency_key), so a retry can never double the debt.
func (uc *FinalizeOrderUseCase) finalizeCash(ctx context.Context, ord *orderdomain.Order, now time.Time) (*orderdomain.Order, error) {
	if err := ord.TransitionTo(orderdomain.StatusCompleted, now); err != nil {
		return nil, err
	}

	pct := uc.commissionProvider.CommissionPercent(ctx)
	if err := uc.paymentTx.WithWebhookTx(ctx, func(txOps paymentdomain.WebhookTx) error {
		if err := txOps.CompleteOrderFinancially(ctx, ord.ID, "complete_order:"+ord.ID, uc.holdSeconds, pct); err != nil {
			return err
		}
		return txOps.UpdateOrderStatus(ctx, ord.ID, string(ord.Status), now)
	}); err != nil {
		uc.logger.Error("cash order auto-completion failed",
			err, "order_id", ord.ID, "driver_id", ord.DriverID)
		return nil, err
	}

	uc.publishCashCompleted(ctx, ord)

	uc.logger.Info("cash order finalized and auto-completed by driver",
		"order_id", ord.ID,
		"driver_id", ord.DriverID,
		"price_total", ord.PriceTotal,
		"commission_percent", pct)
	return ord, nil
}

// publishCashCompleted notifies the client (WebSocket event + push) that the
// cash order is done. Push errors are logged and never roll back the already
// committed completion.
func (uc *FinalizeOrderUseCase) publishCashCompleted(parent context.Context, ord *orderdomain.Order) {
	evPayload := map[string]any{
		"status":      ord.Status,
		"user_id":     ord.UserID,
		"price_total": ord.PriceTotal,
	}
	if ord.DriverID != nil {
		evPayload["driver_id"] = *ord.DriverID
	}
	if err := uc.eventPublisher.Publish(parent, orderdomain.Event{
		Type:    orderdomain.EventCompleted,
		OrderID: ord.ID,
		Payload: evPayload,
	}); err != nil {
		uc.logger.Error("failed to publish completed event for cash order", err, "order_id", ord.ID)
	}

	if uc.pushSender == nil {
		return
	}
	go func() {
		pushCtx, cancel := context.WithTimeout(context.WithoutCancel(parent), 5*time.Second)
		defer cancel()
		title := "Заказ завершён"
		body := fmt.Sprintf("Спасибо, что воспользовались Авро. Оплата наличными: %.2f ₽", float64(ord.PriceTotal)/100)
		data := map[string]string{
			"type":     "order_status",
			"order_id": ord.ID,
			"status":   string(ord.Status),
		}
		if err := uc.pushSender.SendToUser(pushCtx, ord.UserID, "client", title, body, data); err != nil {
			uc.logger.Error("failed to send completed push for cash order", err, "order_id", ord.ID, "user_id", ord.UserID)
		}
	}()
}

// kopecksDiff returns the absolute difference between two kopeck amounts.
func kopecksDiff(a, b int64) int64 {
	if a > b {
		return a - b
	}
	return b - a
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
