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

type fakeTariffListRepo struct {
	tariffs []*Tariff
	err     error
}

func (r *fakeTariffListRepo) GetByTowTruckType(_ context.Context, _ orderdomain.TowTruckType) (*Tariff, error) {
	for _, t := range r.tariffs {
		if t != nil && t.TowTruckType == orderdomain.TowTruckWinch {
			return t, r.err
		}
	}
	return nil, r.err
}
func (r *fakeTariffListRepo) GetAll(context.Context) ([]*Tariff, error)        { return r.tariffs, r.err }
func (r *fakeTariffListRepo) GetByID(context.Context, string) (*Tariff, error) { return nil, nil }
func (r *fakeTariffListRepo) Create(context.Context, *Tariff) error            { return nil }
func (r *fakeTariffListRepo) Update(context.Context, *Tariff) error            { return nil }
func (r *fakeTariffListRepo) Delete(context.Context, string) error             { return nil }

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

func validAllPricesInput() CalculateAllPricesInput {
	return CalculateAllPricesInput{
		OrderID:    "order-1",
		PickupLat:  55.7522,
		PickupLng:  37.6156,
		DropoffLat: 55.7600,
		DropoffLng: 37.6200,
	}
}

func sampleTariffs() []*Tariff {
	return []*Tariff{
		&Tariff{
			ID:           "tariff-winch",
			TowTruckType: orderdomain.TowTruckWinch,
			BasePrice:    250000,
			PricePerKm:   5000,
			MinimumPrice: 200000,
			IsActive:     true,
		},
		&Tariff{
			ID:           "tariff-platform",
			TowTruckType: orderdomain.TowTruckPlatform,
			BasePrice:    300000,
			PricePerKm:   6000,
			MinimumPrice: 300000,
			IsActive:     true,
		},
		&Tariff{
			ID:           "tariff-manipulator",
			TowTruckType: orderdomain.TowTruckManipulator,
			BasePrice:    400000,
			PricePerKm:   8000,
			MinimumPrice: 400000,
			IsActive:     true,
		},
	}
}

func TestServiceCalculateAllPricesHappyPath(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	repo := &fakeTariffListRepo{tariffs: sampleTariffs()}
	// distance = 10 km
	svc := NewService(repo, &fakeDistanceCalc{distance: 10}, fixedClock{t: now})

	all, err := svc.CalculateAllPrices(context.Background(), validAllPricesInput())
	if err != nil {
		t.Fatalf("CalculateAllPrices returned error: %v", err)
	}
	if all.DistanceKm != 10 {
		t.Errorf("DistanceKm = %v, want 10", all.DistanceKm)
	}
	if len(all.Prices) != 3 {
		t.Fatalf("len(Prices) = %d, want 3", len(all.Prices))
	}
	want := map[orderdomain.TowTruckType]int64{
		orderdomain.TowTruckWinch:       300000, // 250000 + 10*5000
		orderdomain.TowTruckPlatform:    360000, // 300000 + 10*6000
		orderdomain.TowTruckManipulator: 480000, // 400000 + 10*8000
	}
	for truckType, price := range want {
		calc, ok := all.Prices[truckType]
		if !ok {
			t.Fatalf("missing price for %q", truckType)
		}
		if calc.TotalPrice != price {
			t.Errorf("TotalPrice[%q] = %d, want %d", truckType, calc.TotalPrice, price)
		}
		if calc.OrderID != "order-1" {
			t.Errorf("OrderID[%q] = %q, want order-1", truckType, calc.OrderID)
		}
	}
}

func TestServiceCalculateAllPricesAppliesMinimum(t *testing.T) {
	repo := &fakeTariffListRepo{
		tariffs: []*Tariff{
			&Tariff{
				ID:           "tariff-winch",
				TowTruckType: orderdomain.TowTruckWinch,
				BasePrice:    100000,
				PricePerKm:   5000,
				MinimumPrice: 150000,
				IsActive:     true,
			},
			&Tariff{
				ID:           "tariff-platform",
				TowTruckType: orderdomain.TowTruckPlatform,
				BasePrice:    100000,
				PricePerKm:   6000,
				MinimumPrice: 180000,
				IsActive:     true,
			},
		},
	}
	// Short route so base + distance would stay below the minimum.
	svc := NewService(repo, &fakeDistanceCalc{distance: 0.1}, fixedClock{})

	all, err := svc.CalculateAllPrices(context.Background(), validAllPricesInput())
	if err != nil {
		t.Fatalf("CalculateAllPrices returned error: %v", err)
	}
	if got := all.Prices[orderdomain.TowTruckWinch].TotalPrice; got != 150000 {
		t.Errorf("winch TotalPrice = %d, want minimum 150000", got)
	}
	if got := all.Prices[orderdomain.TowTruckPlatform].TotalPrice; got != 180000 {
		t.Errorf("platform TotalPrice = %d, want minimum 180000", got)
	}
}

func TestServiceCalculateAllPricesDistanceCalcFailure(t *testing.T) {
	repo := &fakeTariffListRepo{tariffs: sampleTariffs()}
	svc := NewService(repo, &fakeDistanceCalc{err: errors.New("network down")}, fixedClock{})

	_, err := svc.CalculateAllPrices(context.Background(), validAllPricesInput())
	if !errors.Is(err, ErrDistanceCalculationFailed) {
		t.Fatalf("err = %v, want ErrDistanceCalculationFailed", err)
	}
}

func TestServiceCalculateAllPricesRepoError(t *testing.T) {
	wantErr := errors.New("db unreachable")
	svc := NewService(&fakeTariffListRepo{err: wantErr}, &fakeDistanceCalc{distance: 1}, fixedClock{})

	_, err := svc.CalculateAllPrices(context.Background(), validAllPricesInput())
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}

func TestServiceCalculateAllPricesNoActiveTariffs(t *testing.T) {
	svc := NewService(&fakeTariffListRepo{}, &fakeDistanceCalc{distance: 1}, fixedClock{})

	_, err := svc.CalculateAllPrices(context.Background(), validAllPricesInput())
	if !errors.Is(err, ErrTariffNotFound) {
		t.Fatalf("err = %v, want ErrTariffNotFound", err)
	}
}

func TestServiceCalculateAllPricesInvalidInput(t *testing.T) {
	svc := NewService(&fakeTariffListRepo{tariffs: sampleTariffs()}, &fakeDistanceCalc{distance: 1}, fixedClock{})

	tests := []struct {
		name    string
		mutate  func(*CalculateAllPricesInput)
		wantErr error
	}{
		{
			name:    "empty order ID",
			mutate:  func(in *CalculateAllPricesInput) { in.OrderID = "" },
			wantErr: ErrInvalidOrderID,
		},
		{
			name:    "pickup latitude out of range",
			mutate:  func(in *CalculateAllPricesInput) { in.PickupLat = 91 },
			wantErr: ErrInvalidPickupCoordinate,
		},
		{
			name:    "dropoff longitude out of range",
			mutate:  func(in *CalculateAllPricesInput) { in.DropoffLng = 181 },
			wantErr: ErrInvalidDropoffCoordinate,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			in := validAllPricesInput()
			tc.mutate(&in)
			_, err := svc.CalculateAllPrices(context.Background(), in)
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("err = %v, want %v", err, tc.wantErr)
			}
		})
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
