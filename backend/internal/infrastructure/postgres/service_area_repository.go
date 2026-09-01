package postgres

import (
	"context"
	"database/sql"
	"errors"

	servicearea "evik/backend/internal/domain/servicearea"
	"github.com/jackc/pgx/v5/pgconn"
)

type ServiceAreaRepository struct {
	db *sql.DB
}

func NewServiceAreaRepository(db *sql.DB) *ServiceAreaRepository {
	return &ServiceAreaRepository{db: db}
}

const areaColumns = `id, name, COALESCE(slug, ''), min_lat, min_lng, max_lat, max_lng, center_lat, center_lng, radius_km, primary_radius_km, is_active, COALESCE(boundary_geojson, ''), COALESCE(boundary_buffer_km, 7.0)`

func (r *ServiceAreaRepository) CheckPoint(ctx context.Context, lat, lng float64) (*servicearea.ServiceArea, bool, error) {
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
	var bestLevel servicearea.MatchLevel
	var bestDist float64
	var found bool

	for rows.Next() {
		var area servicearea.ServiceArea
		if err := rows.Scan(
			&area.ID, &area.Name, &area.Slug,
			&area.MinLat, &area.MinLng, &area.MaxLat, &area.MaxLng,
			&area.CenterLat, &area.CenterLng, &area.RadiusKM, &area.PrimaryRadiusKM,
			&area.IsActive,
			&area.BoundaryGeoJSON,
			&area.BoundaryBufferKM,
		); err != nil {
			return nil, false, err
		}
		level := area.Match(lat, lng)
		if level == servicearea.MatchNone {
			continue
		}
		// Strict priority: polygon > buffer > circle, regardless of distance.
		if found && level < bestLevel {
			continue
		}
		dist := servicearea.HaversineDistance(area.CenterLat, area.CenterLng, lat, lng)
		// Tie-break within the same level: closest center wins.
		if found && level == bestLevel && dist >= bestDist {
			continue
		}
		best = area
		bestLevel = level
		bestDist = dist
		found = true
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
			&a.CenterLat, &a.CenterLng, &a.RadiusKM, &a.PrimaryRadiusKM,
			&a.IsActive,
			&a.BoundaryGeoJSON,
			&a.BoundaryBufferKM,
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
		&a.CenterLat, &a.CenterLng, &a.RadiusKM, &a.PrimaryRadiusKM,
		&a.IsActive,
		&a.BoundaryGeoJSON,
		&a.BoundaryBufferKM,
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
INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, center_lat, center_lng, radius_km, primary_radius_km, is_active, boundary_geojson, boundary_buffer_km, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())`
	_, err := r.db.ExecContext(ctx, query,
		area.ID, area.Name, area.Slug,
		area.MinLat, area.MinLng, area.MaxLat, area.MaxLng,
		area.CenterLat, area.CenterLng, area.RadiusKM, area.PrimaryRadiusKM,
		area.IsActive,
		area.BoundaryGeoJSON,
		area.BoundaryBufferKM,
	)
	return err
}

func (r *ServiceAreaRepository) Update(ctx context.Context, area servicearea.ServiceArea) error {
	const query = `
UPDATE service_areas
SET name = $2, slug = $3, min_lat = $4, min_lng = $5, max_lat = $6, max_lng = $7,
    center_lat = $8, center_lng = $9, radius_km = $10, primary_radius_km = $11, is_active = $12,
    boundary_geojson = $13, boundary_buffer_km = $14, updated_at = NOW()
WHERE id = $1`
	res, err := r.db.ExecContext(ctx, query,
		area.ID, area.Name, area.Slug,
		area.MinLat, area.MinLng, area.MaxLat, area.MaxLng,
		area.CenterLat, area.CenterLng, area.RadiusKM, area.PrimaryRadiusKM,
		area.IsActive,
		area.BoundaryGeoJSON,
		area.BoundaryBufferKM,
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
	// A city/zone can always be deleted, even while orders reference it. The
	// FK uses ON DELETE SET NULL, so existing orders keep running to
	// completion on their stored coordinates while new orders in the deleted
	// zone become impossible (the zone no longer passes CheckPoint).
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	res, err := tx.ExecContext(ctx, `DELETE FROM service_areas WHERE id = $1`, id)
	if err != nil {
		return mapFKViolation(err, servicearea.ErrAreaInUse)
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

func (r *ServiceAreaRepository) ExistsByName(ctx context.Context, name string) (bool, error) {
	const query = `SELECT EXISTS (SELECT 1 FROM service_areas WHERE LOWER(name) = LOWER($1))`
	var exists bool
	if err := r.db.QueryRowContext(ctx, query, name).Scan(&exists); err != nil {
		return false, err
	}
	return exists, nil
}

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

func mapFKViolation(err error, domainErr error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23503" {
		return domainErr
	}
	return err
}
