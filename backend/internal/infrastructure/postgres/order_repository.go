package postgres

import (
	"context"
	"database/sql"
	"errors"

	orderdomain "evik/backend/internal/domain/order"
)

type OrderRepository struct {
	db *sql.DB
}

func NewOrderRepository(db *sql.DB) *OrderRepository {
	return &OrderRepository{db: db}
}

func (r *OrderRepository) Create(ctx context.Context, ord *orderdomain.Order) error {
	const query = `
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, created_at, updated_at, cancelled_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`
	_, err := r.db.ExecContext(
		ctx,
		query,
		ord.ID,
		ord.UserID,
		ord.DriverID,
		ord.Pickup.Lat,
		ord.Pickup.Lng,
		ord.Dropoff.Lat,
		ord.Dropoff.Lng,
		string(ord.TowTruckType),
		string(ord.Status),
		ord.CreatedAt,
		ord.UpdatedAt,
		ord.CancelledAt,
	)
	return err
}

func (r *OrderRepository) Update(ctx context.Context, ord *orderdomain.Order) error {
	const query = `
UPDATE orders
SET driver_id = $2, tow_truck_type = $3, status = $4, updated_at = $5, cancelled_at = $6
WHERE id = $1`
	_, err := r.db.ExecContext(ctx, query, ord.ID, ord.DriverID, string(ord.TowTruckType), string(ord.Status), ord.UpdatedAt, ord.CancelledAt)
	return err
}

func (r *OrderRepository) GetByID(ctx context.Context, id string) (*orderdomain.Order, error) {
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, created_at, updated_at, cancelled_at
FROM orders
WHERE id = $1`

	var (
		ord          orderdomain.Order
		towTruckType string
		status       string
	)
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&ord.ID,
		&ord.UserID,
		&ord.DriverID,
		&ord.Pickup.Lat,
		&ord.Pickup.Lng,
		&ord.Dropoff.Lat,
		&ord.Dropoff.Lng,
		&towTruckType,
		&status,
		&ord.CreatedAt,
		&ord.UpdatedAt,
		&ord.CancelledAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, orderdomain.ErrOrderNotFound
		}
		return nil, err
	}
	ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
	ord.Status = orderdomain.Status(status)
	return &ord, nil
}

func (r *OrderRepository) ListByStatus(ctx context.Context, status orderdomain.Status, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 20
	}

	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, created_at, updated_at, cancelled_at
FROM orders
WHERE status = $1
ORDER BY created_at ASC
LIMIT $2`

	rows, err := r.db.QueryContext(ctx, query, string(status), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	orders := make([]*orderdomain.Order, 0, limit)
	for rows.Next() {
		var (
			ord          orderdomain.Order
			towTruckType string
			rowStatus    string
		)
		if err := rows.Scan(
			&ord.ID,
			&ord.UserID,
			&ord.DriverID,
			&ord.Pickup.Lat,
			&ord.Pickup.Lng,
			&ord.Dropoff.Lat,
			&ord.Dropoff.Lng,
			&towTruckType,
			&rowStatus,
			&ord.CreatedAt,
			&ord.UpdatedAt,
			&ord.CancelledAt,
		); err != nil {
			return nil, err
		}
		ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
		ord.Status = orderdomain.Status(rowStatus)
		orders = append(orders, &ord)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return orders, nil
}
