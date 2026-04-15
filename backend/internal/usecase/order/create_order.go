package order

import (
	"context"
	"errors"
	"time"

	orderdomain "evik/backend/internal/domain/order"
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

type CreateOrderUseCase struct {
	orderRepo      orderdomain.Repository
	driverMatcher  DriverMatcher
	eventPublisher EventPublisher
	clock          Clock
	idGenerator    IDGenerator
	logger         Logger
}

type CreateOrderInput struct {
	UserID       string
	PickupLat    float64
	PickupLng    float64
	DropoffLat   float64
	DropoffLng   float64
	AutoDispatch bool
}

func NewCreateOrderUseCase(
	orderRepo orderdomain.Repository,
	driverMatcher DriverMatcher,
	eventPublisher EventPublisher,
	clock Clock,
	idGenerator IDGenerator,
	logger Logger,
) *CreateOrderUseCase {
	return &CreateOrderUseCase{
		orderRepo:      orderRepo,
		driverMatcher:  driverMatcher,
		eventPublisher: eventPublisher,
		clock:          clock,
		idGenerator:    idGenerator,
		logger:         logger,
	}
}

func (uc *CreateOrderUseCase) Execute(ctx context.Context, input CreateOrderInput) (*orderdomain.Order, error) {
	pickup := orderdomain.Coordinate{Lat: input.PickupLat, Lng: input.PickupLng}
	dropoff := orderdomain.Coordinate{Lat: input.DropoffLat, Lng: input.DropoffLng}

	ord, err := orderdomain.NewOrder(uc.idGenerator.NewID(), input.UserID, pickup, dropoff, uc.clock.Now())
	if err != nil {
		uc.logger.Error("create order validation failed", err, "user_id", input.UserID)
		return nil, err
	}

	if err := uc.orderRepo.Create(ctx, ord); err != nil {
		uc.logger.Error("failed to persist created order", err, "order_id", ord.ID)
		return nil, err
	}

	if err := ord.TransitionTo(orderdomain.StatusSearching, uc.clock.Now()); err != nil {
		uc.logger.Error("failed to move order to searching", err, "order_id", ord.ID)
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		uc.logger.Error("failed to persist searching order", err, "order_id", ord.ID)
		return nil, err
	}

	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventOrderCreated,
		OrderID: ord.ID,
		Payload: map[string]any{"status": ord.Status},
	}); err != nil {
		uc.logger.Error("failed to publish order created", err, "order_id", ord.ID)
		return nil, err
	}

	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventSearching,
		OrderID: ord.ID,
		Payload: map[string]any{"status": ord.Status},
	}); err != nil {
		uc.logger.Error("failed to publish searching status", err, "order_id", ord.ID)
		return nil, err
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
