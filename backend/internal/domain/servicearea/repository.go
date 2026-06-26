package servicearea

import (
	"context"
	"errors"
)

// ErrNotFound is returned when a service area cannot be located by id.
var ErrNotFound = errors.New("service area not found")

// ErrAreaHasActiveOrders is returned by Delete when the service area still has
// non-terminal orders whose pickup or dropoff falls within its bounds.
var ErrAreaHasActiveOrders = errors.New("service area has active orders")

type Repository interface {
	// CheckPoint reports whether the coordinate falls inside an active area.
	CheckPoint(ctx context.Context, lat, lng float64) (*ServiceArea, bool, error)
	// List returns every service area, active and inactive, ordered by name.
	List(ctx context.Context) ([]ServiceArea, error)
	// GetByID returns a single area or ErrNotFound.
	GetByID(ctx context.Context, id string) (*ServiceArea, error)
	// Create inserts a new area. created_at/updated_at are set to now.
	Create(ctx context.Context, area ServiceArea) error
	// Update overwrites mutable fields of an existing area and bumps updated_at.
	Update(ctx context.Context, area ServiceArea) error
	// SetActive toggles is_active for an area.
	SetActive(ctx context.Context, id string, active bool) error
	// Delete hard-deletes an area, returning ErrAreaHasActiveOrders if any
	// non-terminal order falls within its bounds, or ErrNotFound if absent.
	Delete(ctx context.Context, id string) error
	// ExistsBySlug reports whether an area with the given slug already exists.
	ExistsBySlug(ctx context.Context, slug string) (bool, error)
}
