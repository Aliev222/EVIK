package driver

import (
	"context"

	"evik/backend/internal/domain/order"
)

type Repository interface {
	FindNearestAvailable(ctx context.Context, pickup order.Coordinate, radiusKM float64, limit int) ([]Driver, error)
}
