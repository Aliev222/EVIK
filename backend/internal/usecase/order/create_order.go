package order

import (
	"context"
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

type PricingService interface {
	CalculatePrice(ctx context.Context, input pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error)
}

// PushSender sends push notifications to individual users.
type PushSender interface {
	SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error
}

type CreateOrderUseCase struct {
	orderRepo      orderdomain.Repository
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
	Notes          string
	IdempotencyKey *string
}

func NewCreateOrderUseCase(
	orderRepo orderdomain.Repository,
	pricingService PricingService,
	eventPublisher EventPublisher,
	clock Clock,
	idGenerator IDGenerator,
	logger Logger,
) *CreateOrderUseCase {
	return &CreateOrderUseCase{
		orderRepo:      orderRepo,
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
	ord.Notes = input.Notes
	ord.IdempotencyKey = input.IdempotencyKey
	if input.CityID != "" {
		ord.CityID = &input.CityID
	}

	// Calculate the price BEFORE the first persist: a failed or non-positive
	// price computation must never leave a live zero-priced 'created' row,
	// and an order with price <= 0 must never reach searching/dispatch.
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
		uc.logger.Error("failed to calculate order price", err, "user_id", input.UserID)
		return nil, fmt.Errorf("price calculation failed: %w", err)
	}

	if calculation.TotalPrice <= 0 {
		uc.logger.Error("refusing to create order with non-positive price", orderdomain.ErrNonPositivePrice,
			"user_id", input.UserID,
			"total_price", calculation.TotalPrice)
		return nil, orderdomain.WrapValidation(orderdomain.ErrNonPositivePrice)
	}

	ord.PriceTotal = calculation.TotalPrice

	if err := uc.orderRepo.Create(ctx, ord); err != nil {
		uc.logger.Error("failed to persist created order", err, "order_id", ord.ID)
		return nil, err
	}

	cityID := ""
	if ord.CityID != nil {
		cityID = *ord.CityID
	}

	// Snapshot the values the background goroutine needs BEFORE it starts:
	// the main flow keeps mutating ord (TransitionTo(searching) below writes
	// ord.Status/UpdatedAt), so reading ord inside the goroutine would be a
	// data race. See bug id CREATE-RACE.
	createdOrderID := ord.ID
	createdStatus := ord.Status
	createdUserID := input.UserID
	createdCityID := cityID

	// Publish order created event first
	// Best-effort: order is already in Postgres (source of truth),
	// drivers will find it via polling even without the push event.
	// Delayed 500ms in a goroutine so WebSocket clients have time to
	// connect before the first event is published.
	go func() {
		time.Sleep(500 * time.Millisecond)
		if err := uc.eventPublisher.Publish(context.Background(), orderdomain.Event{
			Type:    orderdomain.EventOrderCreated,
			OrderID: createdOrderID,
			Payload: map[string]any{
				"status":  createdStatus,
				"user_id": createdUserID,
				"city_id": createdCityID,
			},
		}); err != nil {
			uc.logger.Error("failed to publish order created event (non-fatal)", err, "order_id", createdOrderID)
		}
	}()

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
	}

	// Auto-dispatch is handled asynchronously by the dispatch scheduler,
	// which picks up searching orders every 2s and creates offers.
	// No synchronous driver assignment happens here.
	uc.logger.Info("order created successfully", "order_id", ord.ID)
	return ord, nil
}

func (uc *CreateOrderUseCase) GetOrderByKey(ctx context.Context, idempotencyKey string) (*orderdomain.Order, error) {
	return uc.orderRepo.GetByOrderKey(ctx, idempotencyKey)
}


