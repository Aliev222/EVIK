package postgres

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	redisinfra "evik/backend/internal/infrastructure/redis"
	"github.com/lib/pq"
)

type DriverRepository struct {
	db          *sql.DB
	locationRepo *redisinfra.LocationStore
}

func NewDriverRepository(db *sql.DB, locationRepo *redisinfra.LocationStore) *DriverRepository {
	return &DriverRepository{db: db, locationRepo: locationRepo}
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
	COALESCE(d.total_orders, 0) as total_orders,
	(SELECT dd.public_url
	 FROM driver_documents dd
	 JOIN driver_verifications dv ON dv.id = dd.verification_id
	 WHERE dv.user_id = d.user_id AND dd.document_type = 'selfie'
	 LIMIT 1) AS avatar_url
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
		&profile.AvatarURL,
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

func (r *DriverRepository) ListOnlineStale(ctx context.Context, olderThan time.Time, limit int) ([]*driverdomain.Driver, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	const query = `
SELECT id, user_id, status, current_order_id, last_seen_at, updated_at
FROM drivers
WHERE status = $1 AND current_order_id IS NULL AND updated_at < $2
ORDER BY updated_at ASC
LIMIT $3`
	rows, err := r.db.QueryContext(ctx, query, string(driverdomain.StatusOnline), olderThan, limit)
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
			&drv.ID, &drv.UserID, &status, &drv.CurrentOrderID, &drv.LastSeenAt, &drv.UpdatedAt,
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

// ListAllWithProfile returns drivers of any status enriched with user and
// vehicle profile data, most recently seen first. Used by the admin live map,
// which needs every driver (not just online/busy) so it can resolve staleness
// against each driver's last known location.
func (r *DriverRepository) ListAllWithProfile(ctx context.Context, limit int) ([]*driverdomain.DriverProfile, error) {
	if limit <= 0 || limit > 500 {
		limit = 500
	}

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
ORDER BY d.last_seen_at DESC
LIMIT $1`

	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	profiles := make([]*driverdomain.DriverProfile, 0, limit)
	for rows.Next() {
		var (
			profile driverdomain.DriverProfile
			status  string
		)
		if err := rows.Scan(
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
		); err != nil {
			return nil, err
		}
		profile.Status = driverdomain.Status(status)
		profiles = append(profiles, &profile)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return profiles, nil
}

// IsAvailable reports whether the driver can take new offers. A driver is
// available only when online (no active order) AND their current verification
// status is 'approved'. Blocking a driver (driver_verifications.status =
// 'blocked') therefore removes them from the candidate pool immediately even
// when drivers.status is still 'online' — while an in-flight order stays
// untouched and is completed normally. Non-approved states (pending, rejected,
// changes_requested) never enter the candidate pool either.
//
// driver_verifications carries exactly one row per user (unique user_id), but
// historical data may key it by either the driver id or the driver's user_id,
// so the EXISTS matches both.
func (r *DriverRepository) IsAvailable(ctx context.Context, id string) (bool, error) {
	const query = `
SELECT EXISTS(
	SELECT 1
	FROM drivers d
	WHERE d.id = $1
	  AND d.status = $2
	  AND d.current_order_id IS NULL
	  AND EXISTS (
		SELECT 1
		FROM driver_verifications dv
		WHERE dv.user_id IN (d.user_id, d.id)
		  AND dv.status = 'approved'
	  )
)`
	var ok bool
	if err := r.db.QueryRowContext(ctx, query, id, string(driverdomain.StatusOnline)).Scan(&ok); err != nil {
		return false, err
	}
	return ok, nil
}

// AreAvailable checks availability for multiple drivers in a single query (batch).
// Returns a map[driverID]bool. Drivers not found or unavailable map to false.
func (r *DriverRepository) AreAvailable(ctx context.Context, ids []string) (map[string]bool, error) {
	if len(ids) == 0 {
		return map[string]bool{}, nil
	}
	const query = `
SELECT d.id,
       EXISTS(
         SELECT 1
         FROM drivers d2
         WHERE d2.id = d.id
           AND d2.status = $1
           AND d2.current_order_id IS NULL
           AND EXISTS (
             SELECT 1
             FROM driver_verifications dv
             WHERE dv.user_id IN (d2.user_id, d2.id)
               AND dv.status = 'approved'
           )
       ) AS available
FROM drivers d
WHERE d.id = ANY($2)`

	// Build placeholder array for ANY($2)
	rows, err := r.db.QueryContext(ctx, query, string(driverdomain.StatusOnline), pq.StringArray(ids))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]bool, len(ids))
	for rows.Next() {
		var id string
		var available bool
		if err := rows.Scan(&id, &available); err != nil {
			return nil, err
		}
		result[id] = available
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Mark any IDs not returned by the query as unavailable
	for _, id := range ids {
		if _, ok := result[id]; !ok {
			result[id] = false
		}
	}
	return result, nil
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

// ReserveForOfferTx atomically checks that the driver is free (online, no
// current order) AND locks the driver row for the duration of the transaction
// using SELECT ... FOR UPDATE NOWAIT. This prevents two dispatch goroutines
// from offering the same driver to two different orders concurrently.
//
// Returns:
//   - (true, nil)   — driver is free and now row-locked; caller may create the order
//   - (false, nil)  — driver is busy OR already locked by another tx (lock conflict).
//     Caller should try the next candidate instead of failing the whole order.
//   - (false, err)  — unexpected DB error.
func (r *DriverRepository) ReserveForOfferTx(ctx context.Context, tx *sql.Tx, driverID string) (bool, error) {
	const query = `
SELECT id FROM drivers
WHERE id = $1
  AND status = $2
  AND current_order_id IS NULL
FOR UPDATE NOWAIT`

	var id string
	err := tx.QueryRowContext(ctx, query, driverID, string(driverdomain.StatusOnline)).Scan(&id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// Driver not free (already busy / wrong status).
			return false, nil
		}
		// Detect lock-not-available (Postgres 55P03 / pq code "55P03").
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "55P03" {
			// Row already locked by another dispatch tx → treat as "try next".
			return false, nil
		}
		// Any other lock error (e.g. serialized tx failure) → also try next.
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "40001" {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// AssignOrderTx is the tx variant of AssignOrder.
func (r *DriverRepository) AssignOrderTx(ctx context.Context, tx *sql.Tx, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error) {
	const query = `
UPDATE drivers
SET status = $3, current_order_id = $2, last_seen_at = $4, updated_at = $4
WHERE id = $1 AND status = $5 AND current_order_id IS NULL
RETURNING id, user_id, status, current_order_id, last_seen_at, updated_at`

	var (
		drv    driverdomain.Driver
		status string
	)
	err := tx.QueryRowContext(
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
			return nil, driverdomain.ErrDriverBusy
		}
		return nil, err
	}
	drv.Status = driverdomain.Status(status)
	return &drv, nil
}

// ReleaseOrderTx is the tx variant of ReleaseOrder.
func (r *DriverRepository) ReleaseOrderTx(ctx context.Context, tx *sql.Tx, driverID string, orderID string, now time.Time) error {
	const query = `
UPDATE drivers
SET status = $3, current_order_id = NULL, updated_at = $4
WHERE id = $1 AND current_order_id = $2`
	_, err := tx.ExecContext(ctx, query, driverID, orderID, string(driverdomain.StatusOnline), now)
	return err
}

func (r *DriverRepository) FindNearestAvailable(ctx context.Context, pickup orderdomain.Coordinate, radiusKM float64, limit int) ([]driverdomain.Driver, error) {
	nearby, err := r.locationRepo.GetNearbyDrivers(ctx, location.Location{Lat: pickup.Lat, Lng: pickup.Lng}, radiusKM, limit)
	if err != nil {
		return nil, err
	}
	if len(nearby) == 0 {
		return []driverdomain.Driver{}, nil
	}

	ids := make([]string, 0, len(nearby))
	distMap := make(map[string]float64, len(nearby))
	for _, d := range nearby {
		ids = append(ids, d.DriverID)
		distMap[d.DriverID] = d.DistanceKM
	}

	placeholders := make([]string, len(ids))
	args := make([]any, 0, len(ids)+1)
	args = append(args, string(driverdomain.StatusOnline))
	for i, id := range ids {
		placeholders[i] = fmt.Sprintf("$%d", i+2)
		args = append(args, id)
	}

	query := fmt.Sprintf(`
SELECT id, user_id, status, current_order_id, last_seen_at, updated_at
FROM drivers
WHERE status = $1 AND current_order_id IS NULL AND id IN (%s)`, strings.Join(placeholders, ","))

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make([]driverdomain.Driver, 0, len(ids))
	for rows.Next() {
		var drv driverdomain.Driver
		var status string
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
		result = append(result, drv)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	sort.Slice(result, func(i, j int) bool {
		return distMap[result[i].ID] < distMap[result[j].ID]
	})

	if limit > 0 && len(result) > limit {
		result = result[:limit]
	}

	return result, nil
}
