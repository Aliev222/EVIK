package postgres

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	orderdomain "evik/backend/internal/domain/order"
	orderuc "evik/backend/internal/usecase/order"
	"math"
	"time"
)

func (r *OrderRepository) GetTripMeter(ctx context.Context, id string) (*orderuc.TripMeter, error) {
	m := &orderuc.TripMeter{}
	err := r.db.QueryRowContext(ctx, `SELECT lat,lng,observed_at,distance_meters,complete FROM order_trip_meters WHERE order_id=$1`, id).Scan(&m.Lat, &m.Lng, &m.ObservedAt, &m.DistanceMeters, &m.Complete)
	return m, err
}
func (r *OrderRepository) SaveRouteQuote(ctx context.Context, q *orderuc.RouteQuote) error {
	payload, err := json.Marshal(q)
	if err != nil {
		return err
	}
	_, err = r.db.ExecContext(ctx, `INSERT INTO order_route_quotes(id,order_id,user_id,snapshot_updated_at,payload,expires_at) VALUES($1,$2,$3,$4,$5,$6)`, q.ID, q.OrderID, q.UserID, q.Snapshot, payload, q.ExpiresAt)
	return err
}
func (r *OrderRepository) ApplyRouteQuote(ctx context.Context, userID, orderID, quoteID string, now time.Time) (*orderdomain.Order, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	var ord orderdomain.Order
	var status, towTruckType string
	var pickupAddress, dropoffAddress sql.NullString
	err = tx.QueryRowContext(ctx, `
SELECT id,user_id,driver_id,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,
       pickup_address,dropoff_address,tow_truck_type,status,price_total,
       surcharge_amount,updated_at
FROM orders
WHERE id=$1
FOR UPDATE`, orderID).Scan(
		&ord.ID,
		&ord.UserID,
		&ord.DriverID,
		&ord.Pickup.Lat,
		&ord.Pickup.Lng,
		&ord.Dropoff.Lat,
		&ord.Dropoff.Lng,
		&pickupAddress,
		&dropoffAddress,
		&towTruckType,
		&status,
		&ord.PriceTotal,
		&ord.SurchargeAmount,
		&ord.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	ord.Status = orderdomain.Status(status)
	ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
	ord.PickupAddress = scanNullableString(pickupAddress)
	ord.DropoffAddress = scanNullableString(dropoffAddress)
	if ord.UserID != userID {
		return nil, orderuc.ErrRouteChange
	}
	var payload []byte
	var snapshot, expires time.Time
	var applied sql.NullTime
	err = tx.QueryRowContext(ctx, `SELECT payload,snapshot_updated_at,expires_at,applied_at FROM order_route_quotes WHERE id=$1 AND order_id=$2 AND user_id=$3 FOR UPDATE`, quoteID, orderID, userID).Scan(&payload, &snapshot, &expires, &applied)
	if err != nil {
		return nil, orderuc.ErrRouteChange
	}
	if applied.Valid {
		if err = tx.Commit(); err != nil {
			return nil, err
		}
		return r.GetByID(ctx, orderID)
	}
	if !ord.UpdatedAt.Equal(snapshot) || !now.Before(expires) {
		return nil, orderuc.ErrRouteChange
	}
	switch ord.Status {
	case orderdomain.StatusCreated, orderdomain.StatusSearching, orderdomain.StatusAccepted, orderdomain.StatusArrived, orderdomain.StatusInProgress:
	default:
		return nil, orderuc.ErrRouteChange
	}
	var q orderuc.RouteQuote
	if err = json.Unmarshal(payload, &q); err != nil {
		return nil, err
	}
	if err = orderuc.ValidateRouteDraft(&ord, q.Draft); err != nil {
		return nil, err
	}
	// No stale external payment may settle an order at a newly changed price.
	var paymentExists bool
	if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM payments WHERE order_id=$1)`, orderID).Scan(&paymentExists); err != nil {
		return nil, err
	}
	if paymentExists {
		return nil, errors.New("Оплата уже оформлена. Изменение маршрута требует перерасчёта платежа через поддержку")
	}
	_, err = tx.ExecContext(ctx, `UPDATE orders SET pickup_lat=$2,pickup_lng=$3,dropoff_lat=$4,dropoff_lng=$5,pickup_address=$6,dropoff_address=$7,price_total=$8,surcharge_amount=$9,updated_at=$10 WHERE id=$1`, orderID, q.Draft.PickupLat, q.Draft.PickupLng, q.Draft.DropoffLat, q.Draft.DropoffLng, q.Draft.PickupAddress, q.Draft.DropoffAddress, q.Price, q.Surcharge, now)
	if err != nil {
		return nil, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE order_route_quotes SET applied_at=$2 WHERE id=$1`, quoteID, now)
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return r.GetByID(ctx, orderID)
}

// RecordTripLocation accumulates only points owned by the assigned driver
// while the vehicle is loaded. Gaps/jumps invalidate billing instead of
// silently charging a straight-line shortcut through missing GPS data.
func (r *OrderRepository) RecordTripLocation(ctx context.Context, orderID, driverID string, lat, lng float64, now time.Time) error {
	if math.IsNaN(lat) || math.IsNaN(lng) || math.IsInf(lat, 0) || math.IsInf(lng, 0) || math.Abs(lat) > 90 || math.Abs(lng) > 180 {
		return orderuc.ErrTripUnavailable
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var status string
	var assigned sql.NullString
	var pickupLat, pickupLng float64
	var started time.Time
	err = tx.QueryRowContext(ctx, `SELECT status,driver_id,pickup_lat,pickup_lng,updated_at FROM orders WHERE id=$1 FOR UPDATE`, orderID).Scan(&status, &assigned, &pickupLat, &pickupLng, &started)
	if err != nil {
		return err
	}
	if status != "in_progress" || !assigned.Valid || assigned.String != driverID {
		return nil
	}
	m := orderuc.TripMeter{Lat: pickupLat, Lng: pickupLng, ObservedAt: started, Complete: true}
	err = tx.QueryRowContext(ctx, `SELECT lat,lng,observed_at,distance_meters,complete FROM order_trip_meters WHERE order_id=$1`, orderID).Scan(&m.Lat, &m.Lng, &m.ObservedAt, &m.DistanceMeters, &m.Complete)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	dt := now.Sub(m.ObservedAt).Seconds()
	if dt <= 0 {
		return nil
	}
	distance := tripSegmentMeters(m.Lat, m.Lng, lat, lng)
	complete := m.Complete && dt <= 120 && distance/dt <= 55
	if complete {
		m.DistanceMeters += distance
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO order_trip_meters(order_id,lat,lng,observed_at,distance_meters,complete) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(order_id) DO UPDATE SET lat=EXCLUDED.lat,lng=EXCLUDED.lng,observed_at=EXCLUDED.observed_at,distance_meters=EXCLUDED.distance_meters,complete=EXCLUDED.complete`, orderID, lat, lng, now, m.DistanceMeters, complete)
	if err != nil {
		return err
	}
	return tx.Commit()
}
func tripSegmentMeters(lat1, lng1, lat2, lng2 float64) float64 {
	rad := math.Pi / 180
	a := math.Pow(math.Sin((lat2-lat1)*rad/2), 2) + math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Pow(math.Sin((lng2-lng1)*rad/2), 2)
	return 6371000 * 2 * math.Asin(math.Sqrt(math.Min(1, a)))
}
