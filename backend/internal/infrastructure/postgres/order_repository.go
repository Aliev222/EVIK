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
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, status, created_at, updated_at, cancelled_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`
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
SET driver_id = $2, status = $3, updated_at = $4, cancelled_at = $5
WHERE id = $1`
	_, err := r.db.ExecContext(ctx, query, ord.ID, ord.DriverID, string(ord.Status), ord.UpdatedAt, ord.CancelledAt)
	return err
}

func (r *OrderRepository) GetByID(ctx context.Context, id string) (*orderdomain.Order, error) {
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, status, created_at, updated_at, cancelled_at
FROM orders
WHERE id = $1`

	var (
		ord    orderdomain.Order
		status string
	)
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&ord.ID,
		&ord.UserID,
		&ord.DriverID,
		&ord.Pickup.Lat,
		&ord.Pickup.Lng,
		&ord.Dropoff.Lat,
		&ord.Dropoff.Lng,
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
	ord.Status = orderdomain.Status(status)
	return &ord, nil
}
