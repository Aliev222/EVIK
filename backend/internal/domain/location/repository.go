package location

import "context"

type Repository interface {
	SaveLocation(ctx context.Context, driverID string, loc Location) error
	GetNearbyDrivers(ctx context.Context, pickup Location, radiusKM float64, limit int) ([]DriverLocation, error)
	GetLastLocation(ctx context.Context, driverID string) (*Location, error)
}
