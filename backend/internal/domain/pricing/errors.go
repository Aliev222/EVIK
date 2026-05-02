package pricing

import "errors"

var (
	ErrInvalidTariffID             = errors.New("invalid tariff ID")
	ErrInvalidTowTruckType         = errors.New("invalid tow truck type")
	ErrInvalidPrice                = errors.New("invalid price: must be positive")
	ErrMinimumPriceExceedsBase     = errors.New("minimum price cannot exceed base price")
	ErrInvalidOrderID              = errors.New("invalid order ID")
	ErrInvalidPickupCoordinate     = errors.New("invalid pickup coordinate")
	ErrInvalidDropoffCoordinate    = errors.New("invalid dropoff coordinate")
	ErrTariffNotFound              = errors.New("tariff not found")
	ErrInactiveTariff              = errors.New("tariff is inactive")
	ErrDistanceCalculationFailed   = errors.New("distance calculation failed")
)