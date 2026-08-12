package pricing

import (
	"context"
	"math"
	"strconv"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

// This file adds adversarial/edge coverage for the pricing money logic on top
// of service_test.go and tariff_test.go. The focus is the money-safety
// invariant that a price is NEVER computed negative or below the minimum, no
// matter how hostile the input (negative/huge distance, fractional km).

func fixedTariff() *Tariff {
	return &Tariff{
		ID:           "adv-winch",
		TowTruckType: orderdomain.TowTruckWinch,
		BasePrice:    250000,
		PricePerKm:   5000,
		MinimumPrice: 200000,
		IsActive:     true,
	}
}

func formatDist(d float64) string {
	return strconv.FormatFloat(d, 'g', -1, 64)
}

// TestTariffCalculatePrice_NegativeDistanceNeverResultsInNegativePrice guards
// the money invariant when the caller feeds a negative or zero distance.
// The implementation clamps negative distances to zero before computing the
// per-km product, so no negative money can ever escape the calculation and
// the distance price is exactly 0 for any non-positive distance.
func TestTariffCalculatePrice_NegativeDistanceNeverResultsInNegativePrice(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	tariff := fixedTariff()

	for _, dist := range []float64{0, -0.0001, -1, -100, -1e9} {
		t.Run("distance="+formatDist(dist), func(t *testing.T) {
			calc := tariff.CalculatePrice(dist, now)
			if calc.TotalPrice <= 0 {
				t.Errorf("TotalPrice = %d, want > 0 for distance %v", calc.TotalPrice, dist)
			}
			if calc.TotalPrice < calc.AppliedTariff.MinimumPrice {
				t.Errorf("TotalPrice = %d, want >= MinimumPrice %d", calc.TotalPrice, calc.AppliedTariff.MinimumPrice)
			}
			if dist < 0 && calc.DistancePrice != 0 {
				t.Errorf("DistancePrice = %d, want 0 for negative distance %v", calc.DistancePrice, dist)
			}
		})
	}
}

// TestTariffCalculatePrice_HugeDistanceSaturatesAtMaxInt64 feeds a
// distance whose per-km product overflows int64 exactly the way a forged
// client payload or a corrupted route could. The calculation must saturate
// (clamp) at MaxInt64 instead of wrapping to negative money and silently
// collapsing to the minimum price.
func TestTariffCalculatePrice_HugeDistanceSaturatesAtMaxInt64(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)

	tariff := &Tariff{
		ID:           "huge",
		TowTruckType: orderdomain.TowTruckWinch,
		BasePrice:    250000,
		PricePerKm:   1, // 1 kopeck per km is enough: 1e19 km overflows int64
		MinimumPrice: 200000,
		IsActive:     true,
	}

	// 1e18 fits int64: total = distance + base.
	const inRange = int64(1000000000000000000) + 250000
	cases := []struct {
		dist float64
		want int64
	}{
		{dist: 1e18, want: inRange},
		{dist: 1e19, want: math.MaxInt64}, // overflow → saturate, not min-clamp
		{dist: 1e20, want: math.MaxInt64},
		{dist: 1e30, want: math.MaxInt64},
	}
	for _, tc := range cases {
		t.Run(formatDist(tc.dist), func(t *testing.T) {
			calc := tariff.CalculatePrice(tc.dist, now)
			if calc.TotalPrice != tc.want {
				t.Errorf("TotalPrice = %d, want %d (saturated, no silent min-clamp)", calc.TotalPrice, tc.want)
			}
			if calc.TotalPrice <= 0 {
				t.Errorf("TotalPrice = %d (wrapped negative!) for distance %v", calc.TotalPrice, tc.dist)
			}
		})
	}
}

// TestTariffCalculatePrice_HugeBasePlusPerKmAdditionOverflow guards the int64
// addition base + distancePrice for values near math.MaxInt64. The total must
// saturate at MaxInt64 instead of surviving as a wrapped negative number.
func TestTariffCalculatePrice_HugeBasePlusPerKmAdditionOverflow(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	const maxInt64 = int64(^uint64(0) >> 1)

	tariff := &Tariff{
		ID:           "huge-base",
		TowTruckType: orderdomain.TowTruckWinch,
		BasePrice:    maxInt64,
		PricePerKm:   1,
		MinimumPrice: maxInt64,
		IsActive:     true,
	}

	calc := tariff.CalculatePrice(1, now)
	if calc.TotalPrice != maxInt64 {
		t.Fatalf("TotalPrice = %d, want %d (saturated on addition overflow)", calc.TotalPrice, maxInt64)
	}
}

// TestTariffCalculatePrice_FractionalKmHalfUp documents the rounding policy
// on fractional kilometres: half-up (1.5 km * 1 kop/km rounds to 2,
// 0.5 km rounds to 1). See bug id PRICING-ROUND.
func TestTariffCalculatePrice_FractionalKmHalfUp(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)

	tariff := &Tariff{
		ID:           "round",
		TowTruckType: orderdomain.TowTruckWinch,
		BasePrice:    0,
		PricePerKm:   1, // 1 kopeck per km
		MinimumPrice: 0,
		IsActive:     true,
	}

	cases := []struct {
		dist      float64
		wantTotal int64
	}{
		{dist: 1.5, wantTotal: 2}, // 1.5 km * 1 kop/km → half-up 2
		{dist: 0.5, wantTotal: 1}, // 0.5 km → half-up 1
	}
	for _, tc := range cases {
		calc := tariff.CalculatePrice(tc.dist, now)
		if calc.DistancePrice != tc.wantTotal {
			t.Errorf("distance %v: DistancePrice = %d, want %d (half-up)", tc.dist, calc.DistancePrice, tc.wantTotal)
		}
		if calc.TotalPrice != tc.wantTotal {
			t.Errorf("distance %v: TotalPrice = %d, want %d (half-up)", tc.dist, calc.TotalPrice, tc.wantTotal)
		}
	}
}

// TestCalculatePrice_InvalidTruckType documents that the invalid truck type
// scenario is covered by TestServiceCalculatePriceInvalidInput in
// service_test.go. Kept as an explicit guard so a refactor does not silently
// lose the case; it does not duplicate the table test.
func TestCalculatePrice_InvalidTruckType(t *testing.T) {
	svc := NewService(&fakeTariffRepo{}, &fakeDistanceCalc{distance: 1}, fixedClock{})
	_, err := svc.CalculatePrice(context.Background(), CalculatePriceInput{
		OrderID:      "order-1",
		TowTruckType: orderdomain.TowTruckType("bogus"),
	})
	if err == nil {
		t.Fatal("expected error for invalid truck type")
	}
}
