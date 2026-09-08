package order

import (
	"context"
	"errors"
	orderdomain "evik/backend/internal/domain/order"
	pricing "evik/backend/internal/domain/pricing"
	routing "evik/backend/internal/domain/routing"
	"math"
	"time"
)

var ErrRouteChange = errors.New("Заказ изменился или изменение маршрута недоступно. Обновите заказ и рассчитайте стоимость снова")
var ErrTripUnavailable = errors.New("Недостаточно свежих GPS-данных для расчёта пройденного пути. Текущий маршрут сохранён")

type RouteDraft struct {
	PickupLat      float64 `json:"pickup_lat"`
	PickupLng      float64 `json:"pickup_lng"`
	DropoffLat     float64 `json:"dropoff_lat"`
	DropoffLng     float64 `json:"dropoff_lng"`
	PickupAddress  string  `json:"pickup_address"`
	DropoffAddress string  `json:"dropoff_address"`
}
type RouteQuote struct {
	ID             string     `json:"quote_id"`
	OrderID        string     `json:"order_id"`
	UserID         string     `json:"-"`
	Snapshot       time.Time  `json:"-"`
	Draft          RouteDraft `json:"route"`
	Price          int64      `json:"price_total"`
	Surcharge      int64      `json:"surcharge_amount"`
	DistanceMeters float64    `json:"distance_meters"`
	ExpiresAt      time.Time  `json:"expires_at"`
}
type TripMeter struct {
	Lat, Lng, DistanceMeters float64
	ObservedAt               time.Time
	Complete                 bool
}
type RouteChangeStore interface {
	GetByID(context.Context, string) (*orderdomain.Order, error)
	GetTripMeter(context.Context, string) (*TripMeter, error)
	SaveRouteQuote(context.Context, *RouteQuote) error
	ApplyRouteQuote(context.Context, string, string, string, time.Time) (*orderdomain.Order, error)
}
type RouteTariffs interface {
	GetActiveTariff(context.Context, orderdomain.TowTruckType) (*pricing.Tariff, error)
}
type ChangeRouteUseCase struct {
	Store   RouteChangeStore
	Tariffs RouteTariffs
	Routing routing.RoutingService
	Events  EventPublisher
	Clock   Clock
	IDs     IDGenerator
}

func ValidateRouteDraft(ord *orderdomain.Order, d RouteDraft) error {
	for _, v := range []float64{d.PickupLat, d.PickupLng, d.DropoffLat, d.DropoffLng} {
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return ErrRouteChange
		}
	}
	if math.Abs(d.PickupLat) > 90 || math.Abs(d.DropoffLat) > 90 || math.Abs(d.PickupLng) > 180 || math.Abs(d.DropoffLng) > 180 || len(d.PickupAddress) > 1000 || len(d.DropoffAddress) > 1000 {
		return ErrRouteChange
	}
	switch ord.Status {
	case orderdomain.StatusCreated, orderdomain.StatusSearching, orderdomain.StatusAccepted, orderdomain.StatusArrived:
	case orderdomain.StatusInProgress:
		if d.PickupLat != ord.Pickup.Lat || d.PickupLng != ord.Pickup.Lng || d.PickupAddress != ord.PickupAddress {
			return ErrRouteChange
		}
	default:
		return ErrRouteChange
	}
	return nil
}

func (uc *ChangeRouteUseCase) Quote(ctx context.Context, userID, orderID string, d RouteDraft) (*RouteQuote, error) {
	ord, err := uc.Store.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if ord.UserID != userID {
		return nil, ErrRouteChange
	}
	if err = ValidateRouteDraft(ord, d); err != nil {
		return nil, err
	}
	origin := orderdomain.Coordinate{Lat: d.PickupLat, Lng: d.PickupLng}
	travelled := 0.0
	now := uc.Clock.Now()
	if ord.Status == orderdomain.StatusInProgress {
		meter, e := uc.Store.GetTripMeter(ctx, orderID)
		if e != nil || meter == nil || !meter.Complete || now.Sub(meter.ObservedAt) > 60*time.Second {
			return nil, ErrTripUnavailable
		}
		travelled = meter.DistanceMeters
		origin = orderdomain.Coordinate{Lat: meter.Lat, Lng: meter.Lng}
	}
	route, err := uc.Routing.CalculateRoute(ctx, routing.RouteRequest{OrderID: orderID, DriverLocation: origin, ClientLocation: orderdomain.Coordinate{Lat: d.DropoffLat, Lng: d.DropoffLng}})
	if err != nil {
		return nil, err
	}
	if route == nil || math.IsNaN(route.Distance) || math.IsInf(route.Distance, 0) || route.Distance < 0 {
		return nil, ErrRouteChange
	}
	tariff, err := uc.Tariffs.GetActiveTariff(ctx, ord.TowTruckType)
	if err != nil {
		return nil, err
	}
	if tariff == nil || !tariff.IsActive {
		return nil, ErrRouteChange
	}
	distance := travelled + route.Distance
	price := tariff.CalculatePrice(distance/1000, now).TotalPrice
	// Preserve the agreed cross-city pickup supplement; it is not a second base fare.
	if price <= 0 || price > math.MaxInt64-ord.SurchargeAmount {
		return nil, ErrRouteChange
	}
	q := &RouteQuote{ID: uc.IDs.NewID(), OrderID: orderID, UserID: userID, Snapshot: ord.UpdatedAt, Draft: d,
		Price: price + ord.SurchargeAmount, Surcharge: ord.SurchargeAmount, DistanceMeters: distance, ExpiresAt: now.Add(2 * time.Minute)}
	if err = uc.Store.SaveRouteQuote(ctx, q); err != nil {
		return nil, err
	}
	return q, nil
}

func (uc *ChangeRouteUseCase) Confirm(ctx context.Context, userID, orderID, quoteID string) (*orderdomain.Order, error) {
	ord, err := uc.Store.ApplyRouteQuote(ctx, userID, orderID, quoteID, uc.Clock.Now())
	if err != nil {
		return nil, err
	}
	driverID := ""
	if ord.DriverID != nil {
		driverID = *ord.DriverID
	}
	// The durable order remains authoritative if realtime delivery fails; clients also poll.
	if uc.Events != nil {
		_ = uc.Events.Publish(ctx, orderdomain.Event{Type: "order_route_changed", OrderID: ord.ID, Payload: map[string]any{"user_id": ord.UserID, "driver_id": driverID, "price_total": ord.PriceTotal}})
	}
	return ord, nil
}
