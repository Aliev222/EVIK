package driver

import (
	"context"
	"errors"
	"fmt"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
)

type Clock interface {
	Now() time.Time
}

type Logger interface {
	Info(msg string, keyvals ...any)
	Error(msg string, err error, keyvals ...any)
}

type EventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type DriverRepository interface {
	Upsert(ctx context.Context, driver *driverdomain.Driver) error
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
	ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error
}

type OrderRepository interface {
	GetByID(ctx context.Context, id string) (*orderdomain.Order, error)
	Update(ctx context.Context, order *orderdomain.Order) error
}

type LocationRepository interface {
	SaveLocation(ctx context.Context, driverID string, loc location.Location) error
	RemoveDriver(ctx context.Context, driverID string) error
}

// CityDetector maps a coordinate pair to a service-area ID.
type CityDetector interface {
	DetectCity(ctx context.Context, lat, lng float64) (cityID string, found bool, err error)
}

// CityCache persists the driver→city mapping for fast lookup elsewhere.
type CityCache interface {
	SetDriverCity(ctx context.Context, driverID, cityID string) error
}

type SetStatusUseCase struct {
	driverRepo     DriverRepository
	orderRepo      OrderRepository
	locationRepo   LocationRepository
	eventPublisher EventPublisher
	cityDetector   CityDetector
	cityCache      CityCache
	clock          Clock
	logger         Logger
}

type SetStatusInput struct {
	DriverID string
	UserID   string
	Status   driverdomain.Status
	Lat      *float64
	Lng      *float64
}

func NewSetStatusUseCase(
	driverRepo DriverRepository,
	orderRepo OrderRepository,
	locationRepo LocationRepository,
	eventPublisher EventPublisher,
	cityDetector CityDetector,
	cityCache CityCache,
	clock Clock,
	logger Logger,
) *SetStatusUseCase {
	return &SetStatusUseCase{
		driverRepo:     driverRepo,
		orderRepo:      orderRepo,
		locationRepo:   locationRepo,
		eventPublisher: eventPublisher,
		cityDetector:   cityDetector,
		cityCache:      cityCache,
		clock:          clock,
		logger:         logger,
	}
}

func (uc *SetStatusUseCase) Execute(ctx context.Context, input SetStatusInput) (*driverdomain.Driver, error) {
	if input.DriverID == "" {
		return nil, driverdomain.WrapValidation(errors.New("driver id is required"))
	}
	if input.Status != driverdomain.StatusOnline && input.Status != driverdomain.StatusOffline {
		return nil, driverdomain.WrapValidation(fmt.Errorf("unsupported driver status %q", input.Status))
	}

	now := uc.clock.Now()
	current, err := uc.driverRepo.GetByID(ctx, input.DriverID)
	if err != nil && !errors.Is(err, driverdomain.ErrDriverNotFound) {
		return nil, err
	}

	if input.Status == driverdomain.StatusOffline {
		if current != nil && current.CurrentOrderID != nil {
			if err := uc.cancelActiveOrder(ctx, current, now); err != nil {
				return nil, err
			}
		}

		drv := &driverdomain.Driver{
			ID:         input.DriverID,
			UserID:     chooseUserID(input.UserID, current),
			Status:     driverdomain.StatusOffline,
			LastSeenAt: now,
			UpdatedAt:  now,
		}
		if err := uc.driverRepo.Upsert(ctx, drv); err != nil {
			return nil, err
		}
		if err := uc.locationRepo.RemoveDriver(ctx, input.DriverID); err != nil {
			uc.logger.Error("failed to remove offline driver location", err, "driver_id", input.DriverID)
			return nil, err
		}
		return drv, nil
	}

	if current != nil && current.CurrentOrderID != nil && current.Status == driverdomain.StatusBusy {
		if input.Lat != nil && input.Lng != nil {
			if err := uc.locationRepo.SaveLocation(ctx, input.DriverID, location.Location{
				Lat:       *input.Lat,
				Lng:       *input.Lng,
				UpdatedAt: now,
			}); err != nil {
				return nil, err
			}
			uc.cacheDriverCity(ctx, input.DriverID, *input.Lat, *input.Lng)
		}
		return current, nil
	}

	drv := &driverdomain.Driver{
		ID:         input.DriverID,
		UserID:     chooseUserID(input.UserID, current),
		Status:     driverdomain.StatusOnline,
		LastSeenAt: now,
		UpdatedAt:  now,
	}
	if err := uc.driverRepo.Upsert(ctx, drv); err != nil {
		return nil, err
	}
	if input.Lat != nil && input.Lng != nil {
		if err := uc.locationRepo.SaveLocation(ctx, input.DriverID, location.Location{
			Lat:       *input.Lat,
			Lng:       *input.Lng,
			UpdatedAt: now,
		}); err != nil {
			return nil, err
		}
		uc.cacheDriverCity(ctx, input.DriverID, *input.Lat, *input.Lng)
	}
	return drv, nil
}

// cacheDriverCity detects the service area for the given coords and caches it.
// Errors are logged and swallowed — a missed cache write degrades push targeting
// but must never fail a location update.
func (uc *SetStatusUseCase) cacheDriverCity(ctx context.Context, driverID string, lat, lng float64) {
	if uc.cityDetector == nil || uc.cityCache == nil {
		return
	}
	areaID, found, err := uc.cityDetector.DetectCity(ctx, lat, lng)
	if err != nil {
		uc.logger.Error("city detection failed for driver", err, "driver_id", driverID)
		return
	}
	if !found {
		return
	}
	if err := uc.cityCache.SetDriverCity(ctx, driverID, areaID); err != nil {
		uc.logger.Error("failed to cache driver city", err, "driver_id", driverID, "city_id", areaID)
	}
}

func (uc *SetStatusUseCase) cancelActiveOrder(ctx context.Context, drv *driverdomain.Driver, now time.Time) error {
	orderID := *drv.CurrentOrderID
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		if errors.Is(err, orderdomain.ErrOrderNotFound) {
			return uc.driverRepo.ReleaseOrder(ctx, drv.ID, orderID, now)
		}
		return err
	}

	if isTerminal(ord.Status) {
		return uc.driverRepo.ReleaseOrder(ctx, drv.ID, orderID, now)
	}

	if err := ord.TransitionTo(orderdomain.StatusCancelled, now); err != nil {
		return err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return err
	}
	if err := uc.driverRepo.ReleaseOrder(ctx, drv.ID, orderID, now); err != nil {
		return err
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventCancelled,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status":    ord.Status,
			"driver_id": drv.ID,
			"reason":    "driver_offline",
		},
	}); err != nil {
		uc.logger.Error("failed to publish driver offline cancellation", err, "order_id", ord.ID, "driver_id", drv.ID)
		return err
	}
	return nil
}

func chooseUserID(input string, current *driverdomain.Driver) string {
	if input != "" {
		return input
	}
	if current != nil {
		return current.UserID
	}
	return ""
}

func isTerminal(status orderdomain.Status) bool {
	switch status {
	case orderdomain.StatusCompleted, orderdomain.StatusCancelled, orderdomain.StatusNoDriverFound:
		return true
	default:
		return false
	}
}
