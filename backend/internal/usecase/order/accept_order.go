package order

import (
	"context"
	"database/sql"
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

// OrderAcceptStore collects all OrderRepository methods needed by the
// accept usecase. It is a subset that includes both the transactional
// methods (AcceptOrderTx, UpdateTx) and the plain-context GetByID so the
// usecase does not depend on the full orderdomain.Repository.
type OrderAcceptStore interface {
	GetByID(ctx context.Context, id string) (*orderdomain.Order, error)
	AcceptOrderTx(ctx context.Context, tx *sql.Tx, orderID, driverID string) (*orderdomain.Order, error)
	UpdateTx(ctx context.Context, tx *sql.Tx, ord *orderdomain.Order) error
}

// DriverAcceptStore collects all DriverRepository methods needed by the
// accept usecase, including the transactional AssignOrderTx.
type DriverAcceptStore interface {
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
	AssignOrderTx(ctx context.Context, tx *sql.Tx, driverID, orderID string, now time.Time) (*driverdomain.Driver, error)
	ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error
}

type AcceptOrderUseCase struct {
	db             *sql.DB
	orderRepo      OrderAcceptStore
	driverRepo     DriverAcceptStore
	eventPublisher EventPublisher
	pushSender     PushSender
	cityCache      DriverCityCache
	locCache       DriverLocationCache
	cityDetector   CityDetector
	clock          Clock
	logger         Logger
	withTx         func(ctx context.Context, fn func(*sql.Tx) error) error
}

func NewAcceptOrderUseCase(
	db *sql.DB,
	orderRepo OrderAcceptStore,
	driverRepo DriverAcceptStore,
	cityCache DriverCityCache,
	locCache DriverLocationCache,
	cityDetector CityDetector,
	eventPublisher EventPublisher,
	pushSender PushSender,
	clock Clock,
	logger Logger,
) *AcceptOrderUseCase {
	return &AcceptOrderUseCase{
		db:             db,
		orderRepo:      orderRepo,
		driverRepo:     driverRepo,
		cityCache:      cityCache,
		locCache:       locCache,
		cityDetector:   cityDetector,
		eventPublisher: eventPublisher,
		pushSender:     pushSender,
		clock:          clock,
		logger:         logger,
		withTx:         defaultWithTx(db),
	}
}

func defaultWithTx(db *sql.DB) func(ctx context.Context, fn func(*sql.Tx) error) error {
	return func(ctx context.Context, fn func(*sql.Tx) error) error {
		if db == nil {
			return fn(nil)
		}
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		defer tx.Rollback()
		if err := fn(tx); err != nil {
			return err
		}
		return tx.Commit()
	}
}

func (uc *AcceptOrderUseCase) Execute(ctx context.Context, orderID string, driverID string) (*orderdomain.Order, error) {
	// Idempotency: this driver may already hold the order.
	existing, getErr := uc.orderRepo.GetByID(ctx, orderID)
	if getErr == nil && isSameDriverActiveOrder(existing, driverID) {
		return existing, nil
	}

	now := uc.clock.Now()

	err := uc.withTx(ctx, func(tx *sql.Tx) error {
		ord, err := uc.orderRepo.AcceptOrderTx(ctx, tx, orderID, driverID)
		if err != nil {
			return err
		}

		if _, err := uc.driverRepo.AssignOrderTx(ctx, tx, driverID, orderID, now); err != nil {
			return err
		}

		uc.applySurchargeIfCrossCity(ctx, ord, driverID)
		return uc.orderRepo.UpdateTx(ctx, tx, ord)
	})
	if err != nil {
		if errors.Is(err, driverdomain.ErrDriverBusy) {
			recovered := uc.tryRecoverAndRetry(ctx, orderID, driverID, now)
			if !recovered {
				return nil, driverdomain.ErrDriverBusy
			}
			// Recovery released a stale order — retry the full tx once.
			err = uc.withTx(ctx, func(tx *sql.Tx) error {
				ord, err := uc.orderRepo.AcceptOrderTx(ctx, tx, orderID, driverID)
				if err != nil {
					return err
				}
				if _, err := uc.driverRepo.AssignOrderTx(ctx, tx, driverID, orderID, now); err != nil {
					return err
				}
				uc.applySurchargeIfCrossCity(ctx, ord, driverID)
				return uc.orderRepo.UpdateTx(ctx, tx, ord)
			})
			if err != nil {
				return nil, err
			}
		} else {
			return nil, err
		}
	}

	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
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

// tryRecoverAndRetry attempts to release a stale terminal order from the
// driver so the accept retry can succeed. Returns true if recovery released
// something and a retry is worthwhile.
func (uc *AcceptOrderUseCase) tryRecoverAndRetry(ctx context.Context, driverID string, targetOrderID string, now time.Time) bool {
	drv, err := uc.driverRepo.GetByID(ctx, driverID)
	if err != nil {
		return false
	}
	if drv.CurrentOrderID == nil {
		return false
	}
	currentOrderID := *drv.CurrentOrderID
	if currentOrderID == targetOrderID {
		return false
	}
	activeOrder, err := uc.orderRepo.GetByID(ctx, currentOrderID)
	if err != nil {
		if errors.Is(err, orderdomain.ErrOrderNotFound) {
			if releaseErr := uc.driverRepo.ReleaseOrder(ctx, driverID, currentOrderID, now); releaseErr != nil {
				uc.logger.Error("failed to release missing stale order from driver", releaseErr, "driver_id", driverID, "order_id", currentOrderID)
				return false
			}
			return true
		}
		return false
	}
	if !isTerminalOrderStatus(activeOrder.Status) {
		return false
	}
	if releaseErr := uc.driverRepo.ReleaseOrder(ctx, driverID, currentOrderID, now); releaseErr != nil {
		uc.logger.Error("failed to release terminal stale order from driver", releaseErr, "driver_id", driverID, "order_id", currentOrderID)
		return false
	}
	return true
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
	ord.IsCrossCity = true
	// TODO: для карточной оплаты нужно делать доплату через YooKassa
	// или пересчитывать цену до создания платежа
	if ord.PaymentMethod == "cash" {
		original := ord.PriceTotal
		ord.SurchargePercent = 50
		ord.SurchargeAmount = (original*50 + 50) / 100
		ord.PriceTotal = original + ord.SurchargeAmount
		uc.logger.Info("applied cross-city surcharge",
			"order_id", ord.ID,
			"driver_id", driverID,
			"order_city", *ord.CityID,
			"driver_city", driverCity,
			"original_price", original,
			"surcharge_amount", ord.SurchargeAmount,
			"new_total", ord.PriceTotal)
	} else {
		uc.logger.Info("skipped cross-city surcharge for non-cash payment",
			"order_id", ord.ID,
			"payment_method", ord.PaymentMethod)
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

func isTerminalOrderStatus(status orderdomain.Status) bool {
	switch status {
	case orderdomain.StatusCompleted, orderdomain.StatusCancelled, orderdomain.StatusNoDriverFound:
		return true
	default:
		return false
	}
}
