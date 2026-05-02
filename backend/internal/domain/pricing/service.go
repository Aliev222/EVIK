package pricing

import (
	"context"
	"math"
	orderdomain "evik/backend/internal/domain/order"
	"time"
)

// Service defines the pricing service interface
type Service interface {
	// CalculatePrice calculates the price for an order
	CalculatePrice(ctx context.Context, input CalculatePriceInput) (*PriceCalculation, error)

	// GetActiveTariff retrieves the active tariff for a tow truck type
	GetActiveTariff(ctx context.Context, truckType orderdomain.TowTruckType) (*Tariff, error)

	// GetAllTariffs retrieves all active tariffs
	GetAllTariffs(ctx context.Context) ([]*Tariff, error)
}

// Clock interface for time operations
type Clock interface {
	Now() time.Time
}

// DistanceCalculator interface for distance calculations
type DistanceCalculator interface {
	CalculateDistance(lat1, lng1, lat2, lng2 float64) (float64, error)
}

// ServiceImpl implements the pricing service
type ServiceImpl struct {
	repo     Repository
	distCalc DistanceCalculator
	clock    Clock
}

// NewService creates a new pricing service
func NewService(repo Repository, distCalc DistanceCalculator, clock Clock) Service {
	return &ServiceImpl{
		repo:     repo,
		distCalc: distCalc,
		clock:    clock,
	}
}

// CalculatePrice calculates the price for an order
func (s *ServiceImpl) CalculatePrice(ctx context.Context, input CalculatePriceInput) (*PriceCalculation, error) {
	if err := input.IsValid(); err != nil {
		return nil, err
	}

	// Get the tariff for the tow truck type
	tariff, err := s.repo.GetByTowTruckType(ctx, input.TowTruckType)
	if err != nil {
		return nil, err
	}
	if !tariff.IsActive {
		return nil, ErrInactiveTariff
	}

	// Calculate distance
	distance, err := s.distCalc.CalculateDistance(
		input.PickupLat, input.PickupLng,
		input.DropoffLat, input.DropoffLng,
	)
	if err != nil {
		return nil, ErrDistanceCalculationFailed
	}

	// Calculate price using tariff
	calculation := tariff.CalculatePrice(distance, s.clock.Now())
	calculation.OrderID = input.OrderID

	return calculation, nil
}

// GetActiveTariff retrieves the active tariff for a tow truck type
func (s *ServiceImpl) GetActiveTariff(ctx context.Context, truckType orderdomain.TowTruckType) (*Tariff, error) {
	return s.repo.GetByTowTruckType(ctx, truckType)
}

// GetAllTariffs retrieves all active tariffs
func (s *ServiceImpl) GetAllTariffs(ctx context.Context) ([]*Tariff, error) {
	return s.repo.GetAll(ctx)
}

// HaversineDistanceCalculator calculates distance using Haversine formula
type HaversineDistanceCalculator struct{}

// NewHaversineDistanceCalculator creates a new Haversine distance calculator
func NewHaversineDistanceCalculator() DistanceCalculator {
	return &HaversineDistanceCalculator{}
}

// CalculateDistance calculates the great circle distance between two points in kilometers
func (h *HaversineDistanceCalculator) CalculateDistance(lat1, lng1, lat2, lng2 float64) (float64, error) {
	const earthRadius = 6371 // Earth's radius in kilometers

	// Convert degrees to radians
	lat1Rad := lat1 * math.Pi / 180
	lng1Rad := lng1 * math.Pi / 180
	lat2Rad := lat2 * math.Pi / 180
	lng2Rad := lng2 * math.Pi / 180

	// Calculate differences
	dlat := lat2Rad - lat1Rad
	dlng := lng2Rad - lng1Rad

	// Haversine formula
	a := math.Sin(dlat/2)*math.Sin(dlat/2) + math.Cos(lat1Rad)*math.Cos(lat2Rad)*math.Sin(dlng/2)*math.Sin(dlng/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	distance := earthRadius * c

	return distance, nil
}