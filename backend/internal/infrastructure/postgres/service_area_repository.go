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

func (r *ServiceAreaRepository) CheckPoint(ctx context.Context, lat, lng float64) (*servicearea.ServiceArea, bool, error) {
	const query = `
SELECT id, name, min_lat, min_lng, max_lat, max_lng, is_active
FROM service_areas
WHERE is_active = TRUE
	AND $1 BETWEEN min_lat AND max_lat
	AND $2 BETWEEN min_lng AND max_lng
ORDER BY name ASC
LIMIT 1`
	var area servicearea.ServiceArea
	err := r.db.QueryRowContext(ctx, query, lat, lng).Scan(&area.ID, &area.Name, &area.MinLat, &area.MinLng, &area.MaxLat, &area.MaxLng, &area.IsActive)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, false, nil
		}
		return nil, false, err
	}
	return &area, true, nil
}
