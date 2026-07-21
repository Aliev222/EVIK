package postgres

import (
	"context"
	"database/sql"
	"errors"

	servicearea "evik/backend/internal/domain/servicearea"
)

type ServiceAreaRepository struct {
	db *sql.DB
}

func NewServiceAreaRepository(db *sql.DB) *ServiceAreaRepository {
	return &ServiceAreaRepository{db: db}
}

// activeOrdersInAreaSQL counts non-terminal orders whose pickup or dropoff
// falls within a service area's bounds. Orders have no city_id yet, so the
// association is purely geographic via the bounding box.
const activeOrdersInAreaSQL = `
SELECT COUNT(*)
FROM orders o, service_areas s
WHERE s.id = $1
	AND o.status NOT IN ('completed', 'cancelled', 'no_driver_found')
	AND (
		(o.pickup_lat BETWEEN s.min_lat AND s.max_lat AND o.pickup_lng BETWEEN s.min_lng AND s.max_lng)
		OR
		(o.dropoff_lat BETWEEN s.min_lat AND s.max_lat AND o.dropoff_lng BETWEEN s.min_lng AND s.max_lng)
	)`

const areaColumns = `id, name, COALESCE(slug, ''), min_lat, min_lng, max_lat, max_lng, center_lat, center_lng, radius_km, is_active`

func (r *ServiceAreaRepository) CheckPoint(ctx context.Context, lat, lng float64) (*servicearea.ServiceArea, bool, error) {
	// Step 1: coarse bbox prefilter in SQL (fast, index-friendly) —
	// fetch ALL active candidates whose bbox contains the point.
	// Step 2: exact haversine check in Go domain entity for each candidate.
	// Step 3: if multiple zones accept the point, return the closest one.
	const query = `
SELECT ` + areaColumns + `
FROM service_areas
WHERE is_active = TRUE
	AND $1 BETWEEN min_lat AND max_lat
	AND $2 BETWEEN min_lng AND max_lng`
	rows, err := r.db.QueryContext(ctx, query, lat, lng)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	var best servicearea.ServiceArea
	var bestDist float64
	var found bool

	for rows.Next() {
		var area servicearea.ServiceArea
		if err := rows.Scan(
			&area.ID, &area.Name, &area.Slug,
			&area.MinLat, &area.MinLng, &area.MaxLat, &area.MaxLng,
			&area.CenterLat, &area.CenterLng, &area.RadiusKM,
			&area.IsActive,
		); err != nil {
			return nil, false, err
		}
		if !area.Contains(lat, lng) {
			continue
		}
		dist := servicearea.HaversineDistance(area.CenterLat, area.CenterLng, lat, lng)
		if !found || dist < bestDist {
			best = area
			bestDist = dist
			found = true
		}
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	if !found {
		return nil, false, nil
	}
	return &best, true, nil
}

func (r *ServiceAreaRepository) List(ctx context.Context) ([]servicearea.ServiceArea, error) {
	const query = `
SELECT ` + areaColumns + `
FROM service_areas
ORDER BY name ASC`
	rows, err := r.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	areas := make([]servicearea.ServiceArea, 0)
	for rows.Next() {
		var a servicearea.ServiceArea
		if err := rows.Scan(
			&a.ID, &a.Name, &a.Slug,
			&a.MinLat, &a.MinLng, &a.MaxLat, &a.MaxLng,
			&a.CenterLat, &a.CenterLng, &a.RadiusKM,
			&a.IsActive,
		); err != nil {
			return nil, err
		}
		areas = append(areas, a)
	}
	return areas, rows.Err()
}

func (r *ServiceAreaRepository) GetByID(ctx context.Context, id string) (*servicearea.ServiceArea, error) {
	const query = `
SELECT ` + areaColumns + `
FROM service_areas
WHERE id = $1`
	var a servicearea.ServiceArea
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&a.ID, &a.Name, &a.Slug,
		&a.MinLat, &a.MinLng, &a.MaxLat, &a.MaxLng,
		&a.CenterLat, &a.CenterLng, &a.RadiusKM,
		&a.IsActive,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, servicearea.ErrNotFound
		}
		return nil, err
	}
	return &a, nil
}

func (r *ServiceAreaRepository) Create(ctx context.Context, area servicearea.ServiceArea) error {
	const query = `
INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, center_lat, center_lng, radius_km, is_active, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())`
	_, err := r.db.ExecContext(ctx, query,
		area.ID, area.Name, area.Slug,
		area.MinLat, area.MinLng, area.MaxLat, area.MaxLng,
		area.CenterLat, area.CenterLng, area.RadiusKM,
		area.IsActive,
	)
	return err
}

func (r *ServiceAreaRepository) Update(ctx context.Context, area servicearea.ServiceArea) error {
	const query = `
UPDATE service_areas
SET name = $2, slug = $3, min_lat = $4, min_lng = $5, max_lat = $6, max_lng = $7,
    center_lat = $8, center_lng = $9, radius_km = $10, is_active = $11, updated_at = NOW()
WHERE id = $1`
	res, err := r.db.ExecContext(ctx, query,
		area.ID, area.Name, area.Slug,
		area.MinLat, area.MinLng, area.MaxLat, area.MaxLng,
		area.CenterLat, area.CenterLng, area.RadiusKM,
		area.IsActive,
	)
	if err != nil {
		return err
	}
	return ensureAffected(res)
}

func (r *ServiceAreaRepository) SetActive(ctx context.Context, id string, active bool) error {
	const query = `UPDATE service_areas SET is_active = $2, updated_at = NOW() WHERE id = $1`
	res, err := r.db.ExecContext(ctx, query, id, active)
	if err != nil {
		return err
	}
	return ensureAffected(res)
}

func (r *ServiceAreaRepository) Delete(ctx context.Context, id string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var active int
	if err := tx.QueryRowContext(ctx, activeOrdersInAreaSQL, id).Scan(&active); err != nil {
		return err
	}
	if active > 0 {
		return servicearea.ErrAreaHasActiveOrders
	}

	res, err := tx.ExecContext(ctx, `DELETE FROM service_areas WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if err := ensureAffected(res); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *ServiceAreaRepository) ExistsBySlug(ctx context.Context, slug string) (bool, error) {
	const query = `SELECT EXISTS (SELECT 1 FROM service_areas WHERE slug = $1)`
	var exists bool
	if err := r.db.QueryRowContext(ctx, query, slug).Scan(&exists); err != nil {
		return false, err
	}
	return exists, nil
}

// ensureAffected maps a zero-rows-affected result to ErrNotFound.
func ensureAffected(res sql.Result) error {
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return servicearea.ErrNotFound
	}
	return nil
}
