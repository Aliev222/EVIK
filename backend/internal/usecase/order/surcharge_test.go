package order

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	servicearea "evik/backend/internal/domain/servicearea"
)

type fakeCityCache struct {
	cityID string
	err    error
}

func (c *fakeCityCache) GetDriverCity(_ context.Context, driverID string) (string, error) {
	return c.cityID, c.err
}

type fakeLocationCache struct {
	loc *location.Location
	err error
}

func (c *fakeLocationCache) GetLastLocation(_ context.Context, driverID string) (*location.Location, error) {
	return c.loc, c.err
}

type fakeCityDetector struct {
	area *servicearea.ServiceArea
	ok   bool
	err  error
}

func (d *fakeCityDetector) CheckPoint(_ context.Context, lat, lng float64) (*servicearea.ServiceArea, bool, error) {
	return d.area, d.ok, d.err
}

func TestAcceptOrderCrossCitySurchargeAppliedForCard(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	cityID := "city-moscow"
	driverCity := "city-spb"
	basePrice := int64(100000) // 1000 руб в копейках

	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:            "order-1",
			UserID:        "client-1",
			CityID:        &cityID,
			Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:        orderdomain.StatusSearching,
			PriceTotal:    basePrice,
			PaymentMethod: "card",
			CreatedAt:     now,
			UpdatedAt:     now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	cityCache := &fakeCityCache{cityID: driverCity}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, cityCache, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", "driver-1")
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if !ord.IsCrossCity {
		t.Fatal("expected IsCrossCity = true")
	}
	if ord.SurchargeAmount <= 0 {
		t.Fatalf("surcharge_amount = %d, want > 0", ord.SurchargeAmount)
	}
	if ord.SurchargePercent != 50 {
		t.Fatalf("surcharge_percent = %d, want 50", ord.SurchargePercent)
	}
	wantSurcharge := (basePrice*50 + 50) / 100
	if ord.SurchargeAmount != wantSurcharge {
		t.Fatalf("surcharge_amount = %d, want %d", ord.SurchargeAmount, wantSurcharge)
	}
	wantTotal := basePrice + wantSurcharge
	if ord.PriceTotal != wantTotal {
		t.Fatalf("price_total = %d, want %d (base + surcharge)", ord.PriceTotal, wantTotal)
	}
}

func TestAcceptOrderCrossCitySurchargeAppliedForCash(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	cityID := "city-moscow"
	driverCity := "city-spb"
	basePrice := int64(100000)

	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:            "order-1",
			UserID:        "client-1",
			CityID:        &cityID,
			Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:        orderdomain.StatusSearching,
			PriceTotal:    basePrice,
			PaymentMethod: "cash",
			CreatedAt:     now,
			UpdatedAt:     now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	cityCache := &fakeCityCache{cityID: driverCity}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, cityCache, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", "driver-1")
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if !ord.IsCrossCity {
		t.Fatal("expected IsCrossCity = true")
	}
	if ord.SurchargeAmount <= 0 {
		t.Fatalf("surcharge_amount = %d, want > 0", ord.SurchargeAmount)
	}
	wantSurcharge := (basePrice*50 + 50) / 100
	if ord.SurchargeAmount != wantSurcharge {
		t.Fatalf("surcharge_amount = %d, want %d", ord.SurchargeAmount, wantSurcharge)
	}
}

func TestAcceptOrderSameCityNoSurcharge(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	cityID := "city-moscow"
	driverCity := "city-moscow"
	basePrice := int64(100000)

	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:            "order-1",
			UserID:        "client-1",
			CityID:        &cityID,
			Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:        orderdomain.StatusSearching,
			PriceTotal:    basePrice,
			PaymentMethod: "card",
			CreatedAt:     now,
			UpdatedAt:     now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	cityCache := &fakeCityCache{cityID: driverCity}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, cityCache, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", "driver-1")
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.IsCrossCity {
		t.Fatal("expected IsCrossCity = false for same city")
	}
	if ord.SurchargeAmount != 0 {
		t.Fatalf("surcharge_amount = %d, want 0 for same city", ord.SurchargeAmount)
	}
	if ord.PriceTotal != basePrice {
		t.Fatalf("price_total = %d, want %d (no surcharge expected)", ord.PriceTotal, basePrice)
	}
}

func TestAcceptOrderCrossCitySurchargeFallbackViaLocationCache(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	cityID := "city-moscow"
	basePrice := int64(100000)

	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:            "order-1",
			UserID:        "client-1",
			CityID:        &cityID,
			Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:        orderdomain.StatusSearching,
			PriceTotal:    basePrice,
			PaymentMethod: "card",
			CreatedAt:     now,
			UpdatedAt:     now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	// cityCache returns error — must fall back to location cache + city detector
	cityCache := &fakeCityCache{err: sql.ErrNoRows}
	locCache := &fakeLocationCache{
		loc: &location.Location{Lat: 59.93, Lng: 30.31},
	}
	cityDetector := &fakeCityDetector{
		area: &servicearea.ServiceArea{ID: "city-spb"},
		ok:   true,
	}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, cityCache, locCache, cityDetector, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", "driver-1")
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if !ord.IsCrossCity {
		t.Fatal("expected IsCrossCity = true via fallback detection")
	}
	if ord.SurchargeAmount <= 0 {
		t.Fatalf("surcharge_amount = %d, want > 0 after fallback", ord.SurchargeAmount)
	}
}
