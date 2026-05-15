package pricing

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

type fakeTariffRepo struct {
	tariff *Tariff
	err    error
}

func (r *fakeTariffRepo) GetByTowTruckType(_ context.Context, _ orderdomain.TowTruckType) (*Tariff, error) {
	return r.tariff, r.err
}
func (r *fakeTariffRepo) GetAll(context.Context) ([]*Tariff, error)         { return nil, nil }
func (r *fakeTariffRepo) GetByID(context.Context, string) (*Tariff, error)  { return nil, nil }
func (r *fakeTariffRepo) Create(context.Context, *Tariff) error             { return nil }
func (r *fakeTariffRepo) Update(context.Context, *Tariff) error             { return nil }
func (r *fakeTariffRepo) Delete(context.Context, string) error              { return nil }

type fakeDistanceCalc struct {
	distance float64
	err      error
}

func (d *fakeDistanceCalc) CalculateDistance(_, _, _, _ float64) (float64, error) {
	return d.distance, d.err
}

type fixedClock struct{ t time.Time }

func (c fixedClock) Now() time.Time { return c.t }

func validInput() CalculatePriceInput {
	return CalculatePriceInput{
		OrderID:      "order-1",
		PickupLat:    55.7522,
		PickupLng:    37.6156,
		DropoffLat:   55.7600,
		DropoffLng:   37.6200,
		TowTruckType: orderdomain.TowTruckWinch,
	}
}

func TestServiceCalculatePriceHappyPath(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	repo := &fakeTariffRepo{
		tariff: &Tariff{
			ID:           "winch-default",
			TowTruckType: orderdomain.TowTruckWinch,
			BasePrice:    250000,
			PricePerKm:   5000,
			MinimumPrice: 200000,
			IsActive:     true,
		},
	}
	dist := &fakeDistanceCalc{distance: 10}
	svc := NewService(repo, dist, fixedClock{t: now})

	calc, err := svc.CalculatePrice(context.Background(), validInput())
	if err != nil {
		t.Fatalf("CalculatePrice returned error: %v", err)
	}
	if calc.TotalPrice != 300000 {
		t.Errorf("TotalPrice = %d, want 300000", calc.TotalPrice)
	}
	if calc.OrderID != "order-1" {
		t.Errorf("OrderID = %q, want order-1", calc.OrderID)
	}
	if calc.TariffID != "winch-default" {
		t.Errorf("TariffID = %q, want winch-default", calc.TariffID)
	}
}

func TestServiceCalculatePriceInactiveTariff(t *testing.T) {
	repo := &fakeTariffRepo{
		tariff: &Tariff{
			ID:           "winch-default",
			TowTruckType: orderdomain.TowTruckWinch,
			BasePrice:    250000,
			PricePerKm:   5000,
			MinimumPrice: 200000,
			IsActive:     false,
		},
	}
	svc := NewService(repo, &fakeDistanceCalc{distance: 10}, fixedClock{})

	_, err := svc.CalculatePrice(context.Background(), validInput())
	if !errors.Is(err, ErrInactiveTariff) {
		t.Fatalf("err = %v, want ErrInactiveTariff", err)
	}
}

func TestServiceCalculatePriceDistanceCalcFailure(t *testing.T) {
	repo := &fakeTariffRepo{
		tariff: &Tariff{
			ID:           "winch-default",
			TowTruckType: orderdomain.TowTruckWinch,
			BasePrice:    250000,
			PricePerKm:   5000,
			MinimumPrice: 200000,
			IsActive:     true,
		},
	}
	dist := &fakeDistanceCalc{err: errors.New("network down")}
	svc := NewService(repo, dist, fixedClock{})

	_, err := svc.CalculatePrice(context.Background(), validInput())
	if !errors.Is(err, ErrDistanceCalculationFailed) {
		t.Fatalf("err = %v, want ErrDistanceCalculationFailed", err)
	}
}

func TestServiceCalculatePriceRepoError(t *testing.T) {
	wantErr := errors.New("db unreachable")
	repo := &fakeTariffRepo{err: wantErr}
	svc := NewService(repo, &fakeDistanceCalc{distance: 10}, fixedClock{})

	_, err := svc.CalculatePrice(context.Background(), validInput())
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}

func TestServiceCalculatePriceInvalidInput(t *testing.T) {
	svc := NewService(&fakeTariffRepo{}, &fakeDistanceCalc{}, fixedClock{})

	tests := []struct {
		name    string
		input   CalculatePriceInput
		wantErr error
	}{
		{
			name: "empty order ID",
			input: CalculatePriceInput{
				OrderID:      "",
				TowTruckType: orderdomain.TowTruckWinch,
			},
			wantErr: ErrInvalidOrderID,
		},
		{
			name: "invalid truck type",
			input: CalculatePriceInput{
				OrderID:      "order-1",
				TowTruckType: orderdomain.TowTruckType("invalid"),
			},
			wantErr: ErrInvalidTowTruckType,
		},
		{
			name: "pickup latitude out of range",
			input: CalculatePriceInput{
				OrderID:      "order-1",
				TowTruckType: orderdomain.TowTruckWinch,
				PickupLat:    91,
				PickupLng:    0,
				DropoffLat:   0,
				DropoffLng:   0,
			},
			wantErr: ErrInvalidPickupCoordinate,
		},
		{
			name: "dropoff longitude out of range",
			input: CalculatePriceInput{
				OrderID:      "order-1",
				TowTruckType: orderdomain.TowTruckWinch,
				PickupLat:    55,
				PickupLng:    37,
				DropoffLat:   55,
				DropoffLng:   181,
			},
			wantErr: ErrInvalidDropoffCoordinate,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.CalculatePrice(context.Background(), tc.input)
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("err = %v, want %v", err, tc.wantErr)
			}
		})
	}
}
