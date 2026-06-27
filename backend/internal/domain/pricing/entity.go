package pricing

import (
	"time"
	orderdomain "evik/backend/internal/domain/order"
)

// Tariff represents a pricing tariff for a specific tow truck type
type Tariff struct {
	ID           string
	TowTruckType orderdomain.TowTruckType
	BasePrice    int64  // in kopecks: 250000 = 2500 RUB
	PricePerKm   int64  // in kopecks: 5000 = 50 RUB/km
	MinimumPrice int64  // in kopecks: 250000 = 2500 RUB
	IsActive     bool
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// NewTariff creates a new tariff with validation
func NewTariff(id string, truckType orderdomain.TowTruckType, basePrice, pricePerKm, minimumPrice int64, now time.Time) (*Tariff, error) {
	if id == "" {
		return nil, ErrInvalidTariffID
	}
	if !truckType.IsValid() {
		return nil, ErrInvalidTowTruckType
	}
	if basePrice <= 0 || pricePerKm <= 0 || minimumPrice <= 0 {
		return nil, ErrInvalidPrice
	}
	if minimumPrice > basePrice {
		return nil, ErrMinimumPriceExceedsBase
	}

	return &Tariff{
		ID:           id,
		TowTruckType: truckType,
		BasePrice:    basePrice,
		PricePerKm:   pricePerKm,
		MinimumPrice: minimumPrice,
		IsActive:     true,
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

// PriceCalculation represents the result of price calculation
type PriceCalculation struct {
	TariffID        string
	OrderID         string
	DistanceKm      float64
	BasePrice       int64
	DistancePrice   int64
	TotalPrice      int64
	SurchargeAmount  int64
	SurchargePercent int
	AppliedTariff   Tariff
	CalculatedAt    time.Time
}

// CalculatePrice calculates price based on tariff and distance
func (t *Tariff) CalculatePrice(distanceKm float64, now time.Time) *PriceCalculation {
	distancePrice := int64(distanceKm * float64(t.PricePerKm))
	totalPrice := t.BasePrice + distancePrice

	// Apply minimum price
	if totalPrice < t.MinimumPrice {
		totalPrice = t.MinimumPrice
	}

	return &PriceCalculation{
		TariffID:       t.ID,
		DistanceKm:     distanceKm,
		BasePrice:      t.BasePrice,
		DistancePrice:  distancePrice,
		TotalPrice:     totalPrice,
		AppliedTariff:  *t,
		CalculatedAt:   now,
	}
}

// CalculatePriceInput represents input for price calculation
type CalculatePriceInput struct {
	OrderID      string
	PickupLat    float64
	PickupLng    float64
	DropoffLat   float64
	DropoffLng   float64
	TowTruckType orderdomain.TowTruckType
}

// IsValid validates the input
func (input CalculatePriceInput) IsValid() error {
	if input.OrderID == "" {
		return ErrInvalidOrderID
	}
	if !input.TowTruckType.IsValid() {
		return ErrInvalidTowTruckType
	}
	if !isValidCoordinate(input.PickupLat, input.PickupLng) {
		return ErrInvalidPickupCoordinate
	}
	if !isValidCoordinate(input.DropoffLat, input.DropoffLng) {
		return ErrInvalidDropoffCoordinate
	}
	return nil
}

func isValidCoordinate(lat, lng float64) bool {
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}