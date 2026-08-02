package postgres

import (
	"context"
	"database/sql"
	"errors"

	orderdomain "evik/backend/internal/domain/order"
)

type OfferRepository struct {
	db *sql.DB
}

func NewOfferRepository(db *sql.DB) *OfferRepository {
	return &OfferRepository{db: db}
}

func (r *OfferRepository) Create(ctx context.Context, offer *orderdomain.Offer) (bool, error) {
	const query = `
INSERT INTO order_offers (id, order_id, driver_id, round, distance_km, offered_at, expires_at)
VALUES ($1, $2, $3, $4, $5, $6, $7)
ON CONFLICT DO NOTHING
RETURNING id`
	var id string
	err := r.db.QueryRowContext(ctx, query,
		offer.ID,
		offer.OrderID,
		offer.DriverID,
		offer.Round,
		offer.DistanceKM,
		offer.OfferedAt,
		offer.ExpiresAt,
	).Scan(&id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	offer.ID = id
	return true, nil
}

func (r *OfferRepository) GetActiveForOrderAndDriver(ctx context.Context, orderID, driverID string) (*orderdomain.Offer, error) {
	const query = `
SELECT id, order_id, driver_id, round, distance_km, offered_at, expires_at, outcome, resolved_at
FROM order_offers
WHERE order_id = $1 AND driver_id = $2 AND outcome IS NULL AND expires_at > NOW()
LIMIT 1`
	return r.scanOffer(r.db.QueryRowContext(ctx, query, orderID, driverID))
}

func (r *OfferRepository) GetActiveForOrder(ctx context.Context, orderID string) (*orderdomain.Offer, error) {
	const query = `
SELECT id, order_id, driver_id, round, distance_km, offered_at, expires_at, outcome, resolved_at
FROM order_offers
WHERE order_id = $1 AND outcome IS NULL
LIMIT 1`
	return r.scanOffer(r.db.QueryRowContext(ctx, query, orderID))
}

func (r *OfferRepository) GetActiveForDriver(ctx context.Context, driverID string) (*orderdomain.Offer, error) {
	const query = `
SELECT id, order_id, driver_id, round, distance_km, offered_at, expires_at, outcome, resolved_at
FROM order_offers
WHERE driver_id = $1 AND outcome IS NULL
LIMIT 1`
	return r.scanOffer(r.db.QueryRowContext(ctx, query, driverID))
}

func (r *OfferRepository) ExpirePending(ctx context.Context) ([]string, error) {
	const query = `
UPDATE order_offers
SET outcome = 'expired', resolved_at = NOW()
WHERE outcome IS NULL AND expires_at <= NOW()
RETURNING order_id`
	rows, err := r.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orderIDs []string
	for rows.Next() {
		var orderID string
		if err := rows.Scan(&orderID); err != nil {
			return nil, err
		}
		orderIDs = append(orderIDs, orderID)
	}
	return orderIDs, rows.Err()
}

func (r *OfferRepository) ResolveByOrderAndDriver(ctx context.Context, orderID, driverID string, outcome string) error {
	return r.resolveByOrderAndDriver(ctx, r.db, orderID, driverID, outcome)
}

func (r *OfferRepository) ResolveOfferTx(ctx context.Context, tx *sql.Tx, orderID, driverID string, outcome string) error {
	return r.resolveByOrderAndDriver(ctx, tx, orderID, driverID, outcome)
}

func (r *OfferRepository) resolveByOrderAndDriver(ctx context.Context, exec interface{ ExecContext(context.Context, string, ...any) (sql.Result, error) }, orderID, driverID string, outcome string) error {
	const query = `
UPDATE order_offers
SET outcome = $3, resolved_at = NOW()
WHERE order_id = $1 AND driver_id = $2 AND outcome IS NULL`
	res, err := exec.ExecContext(ctx, query, orderID, driverID, outcome)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (r *OfferRepository) ListOrderOfferedDriverIDs(ctx context.Context, orderID string, round int) ([]string, error) {
	const query = `
SELECT driver_id FROM order_offers
WHERE order_id = $1 AND round = $2`
	rows, err := r.db.QueryContext(ctx, query, orderID, round)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *OfferRepository) GetCurrentRound(ctx context.Context, orderID string) (int, error) {
	const query = `SELECT COALESCE(MAX(round), 0) FROM order_offers WHERE order_id = $1`
	var round int
	err := r.db.QueryRowContext(ctx, query, orderID).Scan(&round)
	return round, err
}

func (r *OfferRepository) ListSearchingWithoutOffer(ctx context.Context, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 50
	}
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, price_total, is_cross_city, surcharge_amount, surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method, notes
FROM orders o
WHERE o.status = 'searching'
AND NOT EXISTS (SELECT 1 FROM order_offers f WHERE f.order_id = o.id AND f.outcome IS NULL)
ORDER BY o.created_at ASC
LIMIT $1`
	return r.queryOrders(ctx, query, limit)
}

func (r *OfferRepository) queryOrders(ctx context.Context, query string, args ...any) ([]*orderdomain.Order, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanOrderRows(rows)
}

func scanOrderRows(rows *sql.Rows) ([]*orderdomain.Order, error) {
	orders := make([]*orderdomain.Order, 0)
	for rows.Next() {
		var (
			ord            orderdomain.Order
			pickupAddress  sql.NullString
			dropoffAddress sql.NullString
			cityID         sql.NullString
			towTruckType   string
			rowStatus      string
			expandedAt     sql.NullTime
			paymentMethod  sql.NullString
		)
		if err := rows.Scan(
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
			&rowStatus,
			&ord.PriceTotal,
			&ord.IsCrossCity,
			&ord.SurchargeAmount,
			&ord.SurchargePercent,
			&ord.CreatedAt,
			&ord.UpdatedAt,
			&ord.CancelledAt,
			&cityID,
			&ord.IsExpanded,
			&expandedAt,
			&paymentMethod,
			&ord.Notes,
		); err != nil {
			return nil, err
		}
		ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
		ord.Status = orderdomain.Status(rowStatus)
		ord.PickupAddress = scanNullableString(pickupAddress)
		ord.DropoffAddress = scanNullableString(dropoffAddress)
		ord.PaymentMethod = scanNullableString(paymentMethod)
		if cityID.Valid {
			ord.CityID = &cityID.String
		}
		if expandedAt.Valid {
			t := expandedAt.Time
			ord.ExpandedAt = &t
		}
		orders = append(orders, &ord)
	}
	return orders, rows.Err()
}

func (r *OfferRepository) scanOffer(row scannable) (*orderdomain.Offer, error) {
	var (
		offer      orderdomain.Offer
		distanceKM sql.NullFloat64
		outcome    sql.NullString
		resolvedAt sql.NullTime
	)
	err := row.Scan(
		&offer.ID,
		&offer.OrderID,
		&offer.DriverID,
		&offer.Round,
		&distanceKM,
		&offer.OfferedAt,
		&offer.ExpiresAt,
		&outcome,
		&resolvedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if distanceKM.Valid {
		offer.DistanceKM = &distanceKM.Float64
	}
	if outcome.Valid {
		offer.Outcome = &outcome.String
	}
	if resolvedAt.Valid {
		offer.ResolvedAt = &resolvedAt.Time
	}
	return &offer, nil
}

type scannable interface {
	Scan(dest ...any) error
}
