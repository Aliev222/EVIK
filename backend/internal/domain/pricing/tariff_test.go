package pricing

import (
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

func TestTariffCalculatePrice(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)

	tests := []struct {
		name         string
		basePrice    int64
		pricePerKm   int64
		minimumPrice int64
		distanceKm   float64
		wantTotal    int64
		wantBase     int64
		wantDistance int64
	}{
		{
			name:         "base plus distance above minimum",
			basePrice:    250000,
			pricePerKm:   5000,
			minimumPrice: 200000,
			distanceKm:   10,
			wantTotal:    300000,
			wantBase:     250000,
			wantDistance: 50000,
		},
		{
			name:         "minimum applies when distance is zero and base below minimum",
			basePrice:    100000,
			pricePerKm:   5000,
			minimumPrice: 100000,
			distanceKm:   0,
			wantTotal:    100000,
			wantBase:     100000,
			wantDistance: 0,
		},
		{
			name:         "long distance scales linearly",
			basePrice:    250000,
			pricePerKm:   5000,
			minimumPrice: 250000,
			distanceKm:   100,
			wantTotal:    750000,
			wantBase:     250000,
			wantDistance: 500000,
		},
		{
			name:         "fractional distance is truncated via int64 cast",
			basePrice:    250000,
			pricePerKm:   5000,
			minimumPrice: 250000,
			distanceKm:   3.7,
			wantTotal:    268500,
			wantBase:     250000,
			wantDistance: 18500,
		},
		{
			name:         "minimum kicks in when total below minimum",
			basePrice:    200000,
			pricePerKm:   1000,
			minimumPrice: 200000,
			distanceKm:   2,
			wantTotal:    202000,
			wantBase:     200000,
			wantDistance: 2000,
		},
		{
			name:         "minimum strictly enforced over computed total",
			basePrice:    150000,
			pricePerKm:   1000,
			minimumPrice: 150000,
			distanceKm:   0,
			wantTotal:    150000,
			wantBase:     150000,
			wantDistance: 0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tariff := &Tariff{
				ID:           "t-1",
				TowTruckType: orderdomain.TowTruckWinch,
				BasePrice:    tc.basePrice,
				PricePerKm:   tc.pricePerKm,
				MinimumPrice: tc.minimumPrice,
				IsActive:     true,
			}
			calc := tariff.CalculatePrice(tc.distanceKm, now)

			if calc.TotalPrice != tc.wantTotal {
				t.Errorf("TotalPrice = %d, want %d", calc.TotalPrice, tc.wantTotal)
			}
			if calc.BasePrice != tc.wantBase {
				t.Errorf("BasePrice = %d, want %d", calc.BasePrice, tc.wantBase)
			}
			if calc.DistancePrice != tc.wantDistance {
				t.Errorf("DistancePrice = %d, want %d", calc.DistancePrice, tc.wantDistance)
			}
			if calc.TariffID != "t-1" {
				t.Errorf("TariffID = %q, want t-1", calc.TariffID)
			}
			if calc.DistanceKm != tc.distanceKm {
				t.Errorf("DistanceKm = %v, want %v", calc.DistanceKm, tc.distanceKm)
			}
			if !calc.CalculatedAt.Equal(now) {
				t.Errorf("CalculatedAt = %v, want %v", calc.CalculatedAt, now)
			}
		})
	}
}

func TestNewTariffValidation(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)

	tests := []struct {
		name         string
		id           string
		truckType    orderdomain.TowTruckType
		basePrice    int64
		pricePerKm   int64
		minimumPrice int64
		wantErr      error
	}{
		{
			name:         "valid tariff",
			id:           "t-1",
			truckType:    orderdomain.TowTruckWinch,
			basePrice:    250000,
			pricePerKm:   5000,
			minimumPrice: 200000,
			wantErr:      nil,
		},
		{
			name:    "empty ID",
			id:      "",
			wantErr: ErrInvalidTariffID,
		},
		{
			name:      "invalid truck type",
			id:        "t-1",
			truckType: orderdomain.TowTruckType("unknown"),
			wantErr:   ErrInvalidTowTruckType,
		},
		{
			name:         "zero base price",
			id:           "t-1",
			truckType:    orderdomain.TowTruckWinch,
			basePrice:    0,
			pricePerKm:   5000,
			minimumPrice: 100,
			wantErr:      ErrInvalidPrice,
		},
		{
			name:         "negative price per km",
			id:           "t-1",
			truckType:    orderdomain.TowTruckWinch,
			basePrice:    100000,
			pricePerKm:   -1,
			minimumPrice: 100,
			wantErr:      ErrInvalidPrice,
		},
		{
			name:         "minimum exceeds base",
			id:           "t-1",
			truckType:    orderdomain.TowTruckWinch,
			basePrice:    100000,
			pricePerKm:   5000,
			minimumPrice: 200000,
			wantErr:      ErrMinimumPriceExceedsBase,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tariff, err := NewTariff(tc.id, tc.truckType, tc.basePrice, tc.pricePerKm, tc.minimumPrice, now)
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("err = %v, want %v", err, tc.wantErr)
			}
			if tc.wantErr == nil {
				if tariff == nil {
					t.Fatal("tariff is nil for valid input")
				}
				if !tariff.IsActive {
					t.Error("new tariff should be active by default")
				}
			}
		})
	}
}
