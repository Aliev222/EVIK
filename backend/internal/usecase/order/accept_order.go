package order

import (
	"context"
	"errors"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	servicearea "evik/backend/internal/domain/servicearea"
)

type DriverOrderRepository interface {
	AssignOrder(ctx context.Context, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error)
	ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
}

type DriverCityCache interface {
	GetDriverCity(ctx context.Context, driverID string) (string, error)
}

type DriverLocationCache interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
}

type CityDetector interface {
	CheckPoint(ctx context.Context, lat, lng float64) (*servicearea.ServiceArea, bool, error)
}

type AcceptOrderUseCase struct {
	orderRepo      orderdomain.Repository
	driverRepo     DriverOrderRepository
	eventPublisher EventPublisher
	pushSender     PushSender
	cityCache      DriverCityCache
	locCache       DriverLocationCache
	cityDetector   CityDetector
	clock          Clock
	logger         Logger
}

func NewAcceptOrderUseCase(
	orderRepo orderdomain.Repository,
	driverRepo DriverOrderRepository,
	cityCache DriverCityCache,
	locCache DriverLocationCache,
	cityDetector CityDetector,
	eventPublisher EventPublisher,
	pushSender PushSender,
	clock Clock,
	logger Logger,
) *AcceptOrderUseCase {
	return &AcceptOrderUseCase{
		orderRepo:      orderRepo,
		driverRepo:     driverRepo,
		cityCache:      cityCache,
		locCache:       locCache,
		cityDetector:   cityDetector,
		eventPublisher: eventPublisher,
		pushSender:     pushSender,
		clock:          clock,
		logger:         logger,
	}
}

func (uc *AcceptOrderUseCase) Execute(ctx context.Context, orderID string, driverID string) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.AcceptOrder(ctx, orderID, driverID)
	if err != nil {
		if errors.Is(err, orderdomain.ErrOrderAlreadyTaken) {
			// Idempotency: this driver may already hold the order.
			existing, getErr := uc.orderRepo.GetByID(ctx, orderID)
			if getErr != nil {
				return nil, getErr
			}
			if isSameDriverActiveOrder(existing, driverID) {
				return existing, nil
			}
			return nil, err
		}
		return nil, err
	}

	now := uc.clock.Now()
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

	uc.applySurchargeIfCrossCity(ctx, ord, driverID)
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
			"user_id":   ord.UserID,
		},
	}); err != nil {
		uc.logger.Error("failed to publish accepted status", err, "order_id", ord.ID)
		return nil, err
	}

	uc.notifyClientAccepted(ctx, ord, driverID)

	return ord, nil
}

// notifyClientAccepted fires a "водитель в пути" push at the client when a
// driver takes the order. Errors are logged and swallowed so push failures
// never roll back a successful assignment.
func (uc *AcceptOrderUseCase) notifyClientAccepted(parent context.Context, ord *orderdomain.Order, driverID string) {
	if uc.pushSender == nil {
		return
	}
	pushCtx, cancel := context.WithTimeout(context.WithoutCancel(parent), 5*time.Second)
	defer cancel()

	title := "Водитель в пути"
	body := "Эвакуатор найден и едет к вам"
	data := map[string]string{
		"type":      "order_accepted",
		"order_id":  ord.ID,
		"driver_id": driverID,
	}
	if err := uc.pushSender.SendToUser(pushCtx, ord.UserID, "client", title, body, data); err != nil {
		uc.logger.Error("failed to send accepted push to client", err, "order_id", ord.ID, "user_id", ord.UserID)
	}
}

// applySurchargeIfCrossCity checks whether the accepting driver belongs to a
// different city than the order's origin city. If so, it applies a 50%
// surcharge to the order price. When the driver's city cannot be determined
// from the Redis cache, the method falls back to geo-detecting the city from
// the driver's last known location.
func (uc *AcceptOrderUseCase) applySurchargeIfCrossCity(ctx context.Context, ord *orderdomain.Order, driverID string) {
	if ord.CityID == nil || *ord.CityID == "" || ord.PriceTotal <= 0 {
		return
	}
	var driverCity string
	cityID, err := uc.cityCache.GetDriverCity(ctx, driverID)
	if err == nil && cityID != "" {
		driverCity = cityID
	} else if uc.locCache != nil && uc.cityDetector != nil {
		loc, locErr := uc.locCache.GetLastLocation(ctx, driverID)
		if locErr == nil && loc != nil {
			area, ok, detErr := uc.cityDetector.CheckPoint(ctx, loc.Lat, loc.Lng)
			if detErr == nil && ok {
				driverCity = area.ID
			}
		}
	}
	if driverCity == "" || driverCity == *ord.CityID {
		return
	}
	original := ord.PriceTotal
	ord.IsCrossCity = true
	ord.SurchargePercent = 50
	ord.SurchargeAmount = original * 50 / 100
	ord.PriceTotal = original + ord.SurchargeAmount
	uc.logger.Info("applied cross-city surcharge",
		"order_id", ord.ID,
		"driver_id", driverID,
		"order_city", *ord.CityID,
		"driver_city", driverCity,
		"original_price", original,
		"surcharge_amount", ord.SurchargeAmount,
		"new_total", ord.PriceTotal)
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
