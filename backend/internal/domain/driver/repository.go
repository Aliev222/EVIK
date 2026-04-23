package driver

import (
	"context"
	"time"

	"evik/backend/internal/domain/order"
)

type Repository interface {
	FindNearestAvailable(ctx context.Context, pickup order.Coordinate, radiusKM float64, limit int) ([]Driver, error)
	Upsert(ctx context.Context, driver *Driver) error
	GetByID(ctx context.Context, id string) (*Driver, error)
	IsAvailable(ctx context.Context, id string) (bool, error)
	AssignOrder(ctx context.Context, driverID string, orderID string, now time.Time) (*Driver, error)
	ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error
}
