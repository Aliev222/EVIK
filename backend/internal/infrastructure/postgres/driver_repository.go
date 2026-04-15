package postgres

import (
	"context"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
)

// DriverRepository is intentionally stubbed; production impl can combine PostGIS + Redis geo-index.
type DriverRepository struct{}

func NewDriverRepository() *DriverRepository {
	return &DriverRepository{}
}

func (r *DriverRepository) FindNearestAvailable(ctx context.Context, pickup orderdomain.Coordinate, radiusKM float64, limit int) ([]driverdomain.Driver, error) {
	_ = ctx
	_ = pickup
	_ = radiusKM
	_ = limit
	return []driverdomain.Driver{}, nil
}
