package pricing

import (
	"math"
	"testing"
)

func TestHaversineDistanceCalculator(t *testing.T) {
	calc := NewHaversineDistanceCalculator()

	tests := []struct {
		name        string
		lat1, lng1  float64
		lat2, lng2  float64
		wantKm      float64
		toleranceKm float64
	}{
		{
			name: "same point yields zero",
			lat1: 55.7522, lng1: 37.6156,
			lat2: 55.7522, lng2: 37.6156,
			wantKm:      0,
			toleranceKm: 0.001,
		},
		{
			name: "moscow kremlin to saint petersburg hermitage",
			lat1: 55.7522, lng1: 37.6156,
			lat2: 59.9398, lng2: 30.3146,
			wantKm:      634,
			toleranceKm: 5,
		},
		{
			name: "one degree of latitude on the equator is roughly 111 km",
			lat1: 0, lng1: 0,
			lat2: 1, lng2: 0,
			wantKm:      111,
			toleranceKm: 1,
		},
		{
			name: "one degree of longitude on the equator is roughly 111 km",
			lat1: 0, lng1: 0,
			lat2: 0, lng2: 1,
			wantKm:      111,
			toleranceKm: 1,
		},
		{
			name: "short urban hop is under one km",
			lat1: 55.7522, lng1: 37.6156,
			lat2: 55.7530, lng2: 37.6170,
			wantKm:      0.13,
			toleranceKm: 0.05,
		},
		{
			name: "antipodes are roughly half earth circumference",
			lat1: 0, lng1: 0,
			lat2: 0, lng2: 180,
			wantKm:      20015,
			toleranceKm: 50,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := calc.CalculateDistance(tc.lat1, tc.lng1, tc.lat2, tc.lng2)
			if err != nil {
				t.Fatalf("CalculateDistance returned error: %v", err)
			}
			if math.Abs(got-tc.wantKm) > tc.toleranceKm {
				t.Errorf("distance = %.3f km, want %.3f ± %.3f km", got, tc.wantKm, tc.toleranceKm)
			}
		})
	}
}

func TestHaversineDistanceSymmetry(t *testing.T) {
	calc := NewHaversineDistanceCalculator()

	aToB, _ := calc.CalculateDistance(55.7522, 37.6156, 59.9398, 30.3146)
	bToA, _ := calc.CalculateDistance(59.9398, 30.3146, 55.7522, 37.6156)

	if math.Abs(aToB-bToA) > 0.001 {
		t.Errorf("haversine is not symmetric: A->B = %.6f, B->A = %.6f", aToB, bToA)
	}
}
