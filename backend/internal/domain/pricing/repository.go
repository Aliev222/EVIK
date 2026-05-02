package pricing

import (
	"context"
	orderdomain "evik/backend/internal/domain/order"
)

// Repository defines the interface for tariff data persistence
type Repository interface {
	// GetByTowTruckType retrieves the active tariff for a specific tow truck type
	GetByTowTruckType(ctx context.Context, truckType orderdomain.TowTruckType) (*Tariff, error)

	// GetAll retrieves all active tariffs
	GetAll(ctx context.Context) ([]*Tariff, error)

	// GetByID retrieves a tariff by ID
	GetByID(ctx context.Context, id string) (*Tariff, error)

	// Create creates a new tariff
	Create(ctx context.Context, tariff *Tariff) error

	// Update updates an existing tariff
	Update(ctx context.Context, tariff *Tariff) error

	// Delete soft-deletes a tariff by setting IsActive to false
	Delete(ctx context.Context, id string) error
}