package postgres

import (
	"context"
	"database/sql"
	"errors"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
)

type DriverRepository struct {
	db *sql.DB
}

func NewDriverRepository(db *sql.DB) *DriverRepository {
	return &DriverRepository{db: db}
}

func (r *DriverRepository) Upsert(ctx context.Context, driver *driverdomain.Driver) error {
	const query = `
INSERT INTO drivers (id, user_id, status, current_order_id, last_seen_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (id) DO UPDATE
SET user_id = EXCLUDED.user_id,
	status = EXCLUDED.status,
	current_order_id = EXCLUDED.current_order_id,
	last_seen_at = EXCLUDED.last_seen_at,
	updated_at = EXCLUDED.updated_at`
	_, err := r.db.ExecContext(
		ctx,
		query,
		driver.ID,
		driver.UserID,
		string(driver.Status),
		driver.CurrentOrderID,
		driver.LastSeenAt,
		driver.UpdatedAt,
	)
	return err
}

func (r *DriverRepository) GetByID(ctx context.Context, id string) (*driverdomain.Driver, error) {
	const query = `
SELECT id, user_id, status, current_order_id, last_seen_at, updated_at
FROM drivers
WHERE id = $1`

	var (
		drv    driverdomain.Driver
		status string
	)
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&drv.ID,
		&drv.UserID,
		&status,
		&drv.CurrentOrderID,
		&drv.LastSeenAt,
		&drv.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, driverdomain.ErrDriverNotFound
		}
		return nil, err
	}
	drv.Status = driverdomain.Status(status)
	return &drv, nil
}

func (r *DriverRepository) GetProfileByID(ctx context.Context, id string) (*driverdomain.DriverProfile, error) {
	const query = `
SELECT
	d.id,
	d.user_id,
	d.status,
	d.current_order_id,
	d.last_seen_at,
	d.updated_at,
	COALESCE(u.full_name, '') as full_name,
	COALESCE(u.phone, '') as phone,
	COALESCE(d.vehicle_plate, '') as vehicle_plate,
	COALESCE(d.vehicle_model, '') as vehicle_model,
	COALESCE(d.vehicle_type, '') as vehicle_type,
	COALESCE(d.rating_average, 0.0) as rating_average,
	COALESCE(d.rating_count, 0) as rating_count,
	COALESCE(d.total_orders, 0) as total_orders
FROM drivers d
LEFT JOIN users u ON u.id = d.user_id
WHERE d.id = $1`

	var (
		profile driverdomain.DriverProfile
		status  string
	)
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&profile.ID,
		&profile.UserID,
		&status,
		&profile.CurrentOrderID,
		&profile.LastSeenAt,
		&profile.UpdatedAt,
		&profile.FullName,
		&profile.Phone,
		&profile.VehiclePlate,
		&profile.VehicleModel,
		&profile.VehicleType,
		&profile.RatingAverage,
		&profile.RatingCount,
		&profile.TotalOrders,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, driverdomain.ErrDriverNotFound
		}
		return nil, err
	}
	profile.Status = driverdomain.Status(status)
	return &profile, nil
}

func (r *DriverRepository) ListActive(ctx context.Context, limit int) ([]*driverdomain.Driver, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}

	const query = `
SELECT id, user_id, status, current_order_id, last_seen_at, updated_at
FROM drivers
WHERE status IN ($1, $2)
ORDER BY last_seen_at DESC
LIMIT $3`

	rows, err := r.db.QueryContext(ctx, query, string(driverdomain.StatusOnline), string(driverdomain.StatusBusy), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	drivers := make([]*driverdomain.Driver, 0, limit)
	for rows.Next() {
		var (
			drv    driverdomain.Driver
			status string
		)
		if err := rows.Scan(
			&drv.ID,
			&drv.UserID,
			&status,
			&drv.CurrentOrderID,
			&drv.LastSeenAt,
			&drv.UpdatedAt,
		); err != nil {
			return nil, err
		}
		drv.Status = driverdomain.Status(status)
		drivers = append(drivers, &drv)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return drivers, nil
}

func (r *DriverRepository) IsAvailable(ctx context.Context, id string) (bool, error) {
	drv, err := r.GetByID(ctx, id)
	if err != nil {
		if errors.Is(err, driverdomain.ErrDriverNotFound) {
			return false, nil
		}
		return false, err
	}
	return drv.IsAvailable(), nil
}

func (r *DriverRepository) AssignOrder(ctx context.Context, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error) {
	const query = `
UPDATE drivers
SET status = $3, current_order_id = $2, last_seen_at = $4, updated_at = $4
WHERE id = $1 AND status = $5 AND current_order_id IS NULL
RETURNING id, user_id, status, current_order_id, last_seen_at, updated_at`

	var (
		drv    driverdomain.Driver
		status string
	)
	err := r.db.QueryRowContext(
		ctx,
		query,
		driverID,
		orderID,
		string(driverdomain.StatusBusy),
		now,
		string(driverdomain.StatusOnline),
	).Scan(
		&drv.ID,
		&drv.UserID,
		&status,
		&drv.CurrentOrderID,
		&drv.LastSeenAt,
		&drv.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, driverdomain.ErrDriverUnavailable
		}
		return nil, err
	}
	drv.Status = driverdomain.Status(status)
	return &drv, nil
}

func (r *DriverRepository) ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error {
	const query = `
UPDATE drivers
SET status = $3, current_order_id = NULL, updated_at = $4
WHERE id = $1 AND current_order_id = $2`
	_, err := r.db.ExecContext(ctx, query, driverID, orderID, string(driverdomain.StatusOnline), now)
	return err
}

func (r *DriverRepository) FindNearestAvailable(ctx context.Context, pickup orderdomain.Coordinate, radiusKM float64, limit int) ([]driverdomain.Driver, error) {
	_ = ctx
	_ = pickup
	_ = radiusKM
	_ = limit
	return []driverdomain.Driver{}, nil
}
