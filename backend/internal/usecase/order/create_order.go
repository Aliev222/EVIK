package order

import (
	"context"
	"errors"
	"fmt"
	"time"

	orderdomain "evik/backend/internal/domain/order"
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

// PushSender sends push notifications to individual users.
type PushSender interface {
	SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error
}

type CreateOrderUseCase struct {
	orderRepo      orderdomain.Repository
	driverMatcher  DriverMatcher
	pricingService PricingService
	eventPublisher EventPublisher
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
	PaymentMethod  string
	AutoDispatch   bool
	CityID         string
	IdempotencyKey *string
}

func NewCreateOrderUseCase(
	orderRepo orderdomain.Repository,
	driverMatcher DriverMatcher,
	pricingService PricingService,
	eventPublisher EventPublisher,
	clock Clock,
	idGenerator IDGenerator,
	logger Logger,
) *CreateOrderUseCase {
	return &CreateOrderUseCase{
		orderRepo:      orderRepo,
		driverMatcher:  driverMatcher,
		pricingService: pricingService,
		eventPublisher: eventPublisher,
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
	ord.PaymentMethod = input.PaymentMethod
	ord.PriceTotal = 0
	ord.IdempotencyKey = input.IdempotencyKey
	if input.CityID != "" {
		ord.CityID = &input.CityID
	}

	if err := uc.orderRepo.Create(ctx, ord); err != nil {
		uc.logger.Error("failed to persist created order", err, "order_id", ord.ID)
		return nil, err
	}

	cityID := ""
	if ord.CityID != nil {
		cityID = *ord.CityID
	}

	// Publish order created event first
	// Best-effort: order is already in Postgres (source of truth),
	// drivers will find it via polling even without the push event.
	// Delayed 500ms in a goroutine so WebSocket clients have time to
	// connect before the first event is published.
	go func() {
		time.Sleep(500 * time.Millisecond)
		if err := uc.eventPublisher.Publish(context.Background(), orderdomain.Event{
			Type:    orderdomain.EventOrderCreated,
			OrderID: ord.ID,
			Payload: map[string]any{
				"status":  ord.Status,
				"user_id": input.UserID,
				"city_id": cityID,
			},
		}); err != nil {
			uc.logger.Error("failed to publish order created event (non-fatal)", err, "order_id", ord.ID)
		}
	}()

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

	ord.PriceTotal = calculation.TotalPrice

	uc.logger.Info("order pricing calculated",
		"order_id", ord.ID,
		"total_price", calculation.TotalPrice,
		"payment_method", input.PaymentMethod,
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

func (uc *CreateOrderUseCase) GetOrderByKey(ctx context.Context, idempotencyKey string) (*orderdomain.Order, error) {
	return uc.orderRepo.GetByOrderKey(ctx, idempotencyKey)
}


