package order

import (
	"context"
	"errors"
	"fmt"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	pricingdomain "evik/backend/internal/domain/pricing"
)

type Logger interface {
	Info(msg string, keyvals ...any)
	Error(msg string, err error, keyvals ...any)
}

type Clock interface {
	Now() time.Time
}

type IDGenerator interface {
	NewID() string
}

type EventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type DriverMatcher interface {
	Execute(ctx context.Context, orderID string) (*orderdomain.Order, error)
}

type PricingService interface {
	CalculatePrice(ctx context.Context, input pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error)
}

type PaymentService interface {
	CreateTransaction(ctx context.Context, userID, orderID, title string, amount int64) (*paymentdomain.PaymentTransaction, error)
}

// PushSender mirrors the surface of fcm.PushSender so this package can call
// out to the FCM layer without importing it.
type PushSender interface {
	SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error
	BroadcastToAvailableDrivers(ctx context.Context, title, body string, data map[string]string) error
	BroadcastToDriversInCity(ctx context.Context, cityID, title, body string, data map[string]string) error
}

type CreateOrderUseCase struct {
	orderRepo      orderdomain.Repository
	driverMatcher  DriverMatcher
	pricingService PricingService
	paymentService PaymentService
	eventPublisher EventPublisher
	pushSender     PushSender
	clock          Clock
	idGenerator    IDGenerator
	logger         Logger
}

type CreateOrderInput struct {
	UserID         string
	PickupLat      float64
	PickupLng      float64
	DropoffLat     float64
	DropoffLng     float64
	PickupAddress  string
	DropoffAddress string
	TowTruckType   orderdomain.TowTruckType
	AutoDispatch   bool
	CityID         string
}

func NewCreateOrderUseCase(
	orderRepo orderdomain.Repository,
	driverMatcher DriverMatcher,
	pricingService PricingService,
	paymentService PaymentService,
	eventPublisher EventPublisher,
	pushSender PushSender,
	clock Clock,
	idGenerator IDGenerator,
	logger Logger,
) *CreateOrderUseCase {
	return &CreateOrderUseCase{
		orderRepo:      orderRepo,
		driverMatcher:  driverMatcher,
		pricingService: pricingService,
		paymentService: paymentService,
		eventPublisher: eventPublisher,
		pushSender:     pushSender,
		clock:          clock,
		idGenerator:    idGenerator,
		logger:         logger,
	}
}

func (uc *CreateOrderUseCase) Execute(ctx context.Context, input CreateOrderInput) (*orderdomain.Order, error) {
	pickup := orderdomain.Coordinate{Lat: input.PickupLat, Lng: input.PickupLng}
	dropoff := orderdomain.Coordinate{Lat: input.DropoffLat, Lng: input.DropoffLng}

	ord, err := orderdomain.NewOrder(uc.idGenerator.NewID(), input.UserID, pickup, dropoff, input.TowTruckType, uc.clock.Now())
	if err != nil {
		uc.logger.Error("create order validation failed", err, "user_id", input.UserID)
		return nil, err
	}
	ord.PickupAddress = input.PickupAddress
	ord.DropoffAddress = input.DropoffAddress
	if input.CityID != "" {
		ord.CityID = &input.CityID
	}

	if err := uc.orderRepo.Create(ctx, ord); err != nil {
		uc.logger.Error("failed to persist created order", err, "order_id", ord.ID)
		return nil, err
	}

	// Publish order created event first
	// Best-effort: order is already in Postgres (source of truth),
	// drivers will find it via polling even without the push event.
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventOrderCreated,
		OrderID: ord.ID,
		Payload: map[string]any{"status": ord.Status},
	}); err != nil {
		uc.logger.Error("failed to publish order created event (non-fatal)", err, "order_id", ord.ID)
	}

	// Calculate price for the order
	priceInput := pricingdomain.CalculatePriceInput{
		OrderID:      ord.ID,
		PickupLat:    input.PickupLat,
		PickupLng:    input.PickupLng,
		DropoffLat:   input.DropoffLat,
		DropoffLng:   input.DropoffLng,
		TowTruckType: input.TowTruckType,
	}

	calculation, err := uc.pricingService.CalculatePrice(ctx, priceInput)
	if err != nil {
		uc.logger.Error("failed to calculate order price", err, "order_id", ord.ID)
		return nil, fmt.Errorf("price calculation failed: %w", err)
	}

	// Create payment transaction for the order
	transactionTitle := fmt.Sprintf("Заказ эвакуатора %s", input.TowTruckType)
	transaction, err := uc.paymentService.CreateTransaction(ctx, input.UserID, ord.ID, transactionTitle, calculation.TotalPrice)
	if err != nil {
		uc.logger.Error("failed to create payment transaction", err, "order_id", ord.ID, "amount", calculation.TotalPrice)
		return nil, fmt.Errorf("payment transaction creation failed: %w", err)
	}

	uc.logger.Info("order pricing calculated and payment created",
		"order_id", ord.ID,
		"total_price", calculation.TotalPrice,
		"transaction_id", transaction.ID,
		"distance_km", calculation.DistanceKm,
		"tariff_id", calculation.TariffID)

	// Transition to searching status and update database
	if err := ord.TransitionTo(orderdomain.StatusSearching, uc.clock.Now()); err != nil {
		uc.logger.Error("failed to move order to searching", err, "order_id", ord.ID)
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		uc.logger.Error("failed to persist searching order", err, "order_id", ord.ID)
		return nil, err
	}

	// Publish searching event to notify drivers (best-effort — order is already in DB)
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventSearching,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status": ord.Status,
			"order":  ord,
		},
	}); err != nil {
		uc.logger.Error("failed to publish searching event", err, "order_id", ord.ID)
	}

	// Fan a push out to every currently-available driver. Mirrors the WS
	// "searching" event for drivers whose app is backgrounded. Errors are
	// logged but never propagated — a failed FCM broadcast must not abort
	// order creation.
	uc.broadcastNewOrderPush(ctx, ord, calculation.TotalPrice)

	if !input.AutoDispatch {
		uc.logger.Info("order created without auto dispatch", "order_id", ord.ID)
		return ord, nil
	}

	updated, err := uc.driverMatcher.Execute(ctx, ord.ID)
	if err != nil {
		uc.logger.Error("matching did not find driver", err, "order_id", ord.ID)
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
			return nil, err
		}
		return ord, nil
	}
	uc.logger.Info("order created successfully", "order_id", ord.ID)
	return updated, nil
}

// broadcastNewOrderPush sends "новый заказ" notification to every available
// driver. Payload includes order_id and price so the Flutter app can render
// a richer notification or jump straight into the order screen on tap.
//
// The push goes out on a detached context with a 5s timeout so the HTTP
// request that triggered order creation is not held hostage by a slow FCM
// round-trip, and is skipped entirely when no sender is wired (test paths).
func (uc *CreateOrderUseCase) broadcastNewOrderPush(parent context.Context, ord *orderdomain.Order, priceKopecks int64) {
	if uc.pushSender == nil {
		return
	}
	pushCtx, cancel := context.WithTimeout(context.WithoutCancel(parent), 5*time.Second)
	defer cancel()

	title := "Новый заказ"
	body := fmt.Sprintf("Эвакуатор %s — %.0f ₽", ord.TowTruckType, float64(priceKopecks)/100)
	data := map[string]string{
		"type":           "new_order",
		"order_id":       ord.ID,
		"tow_truck_type": string(ord.TowTruckType),
		"price_kopecks":  fmt.Sprintf("%d", priceKopecks),
	}
	var pushErr error
	if ord.CityID != nil && *ord.CityID != "" {
		pushErr = uc.pushSender.BroadcastToDriversInCity(pushCtx, *ord.CityID, title, body, data)
	} else {
		pushErr = uc.pushSender.BroadcastToAvailableDrivers(pushCtx, title, body, data)
	}
	if pushErr != nil {
		uc.logger.Error("failed to broadcast new order push", pushErr, "order_id", ord.ID)
	}
}
