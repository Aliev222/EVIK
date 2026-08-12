package pricing

import (
	"math"
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
	// A negative distance is a broken input, never a reason to mint money:
	// clamp to zero so the per-km product can never go negative.
	if distanceKm < 0 {
		distanceKm = 0
	}

	// Half-up rounding of the per-km product (1.5 km * 1 kop/km = 2 kop).
	// Saturate at MaxInt64 so a hostile/huge distance cannot wrap the
	// float→int conversion into negative money that would then silently
	// collapse to the minimum price.
	var distancePrice int64
	if raw := distanceKm * float64(t.PricePerKm); raw >= float64(math.MaxInt64) {
		distancePrice = math.MaxInt64
	} else {
		distancePrice = int64(math.Round(raw))
	}

	totalPrice := t.BasePrice + distancePrice
	if totalPrice < t.BasePrice {
		// int64 addition overflow: base + distance wrapped past MaxInt64.
		totalPrice = math.MaxInt64
	}

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

// CalculateAllPricesInput represents input for calculating prices for every
// active tow truck type for a single route. The server is the only price
// authority: one estimate request returns all type prices at once, so the
// client never has to recompute on tow-truck-type switch.
type CalculateAllPricesInput struct {
	OrderID    string
	PickupLat  float64
	PickupLng  float64
	DropoffLat float64
	DropoffLng float64
}

// IsValid validates the input
func (input CalculateAllPricesInput) IsValid() error {
	if input.OrderID == "" {
		return ErrInvalidOrderID
	}
	if !isValidCoordinate(input.PickupLat, input.PickupLng) {
		return ErrInvalidPickupCoordinate
	}
	if !isValidCoordinate(input.DropoffLat, input.DropoffLng) {
		return ErrInvalidDropoffCoordinate
	}
	return nil
}

// AllPricesCalculation is the result of estimating a route for every active
// tow truck type. Prices are keyed by tow truck type and each entry carries
// the full breakdown (base + distance, minimum applied).
type AllPricesCalculation struct {
	DistanceKm float64
	Prices     map[orderdomain.TowTruckType]*PriceCalculation
}

func isValidCoordinate(lat, lng float64) bool {
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}