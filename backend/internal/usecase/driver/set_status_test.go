package driver

import (
	"context"
	"testing"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
)

func TestSetStatusOnlinePersistsDriverAndLocation(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	driverRepo := newFakeDriverRepository()
	orderRepo := newFakeOrderRepository()
	locationRepo := &fakeLocationRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, publisher, nil, nil, fakeClock{now: now}, fakeLogger{})

	lat := 55.75
	lng := 37.62
	drv, err := uc.Execute(context.Background(), SetStatusInput{
		DriverID: "driver-1",
		UserID:   "user-1",
		Status:   driverdomain.StatusOnline,
		Lat:      &lat,
		Lng:      &lng,
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if drv.Status != driverdomain.StatusOnline {
		t.Fatalf("status = %q, want %q", drv.Status, driverdomain.StatusOnline)
	}
	if drv.CurrentOrderID != nil {
		t.Fatalf("current order = %v, want nil", *drv.CurrentOrderID)
	}
	if locationRepo.savedDriverID != "driver-1" {
		t.Fatalf("saved location driver = %q, want driver-1", locationRepo.savedDriverID)
	}
	if locationRepo.savedLocation.Lat != lat || locationRepo.savedLocation.Lng != lng {
		t.Fatalf("saved location = %+v, want lat=%v lng=%v", locationRepo.savedLocation, lat, lng)
	}
}

func TestSetStatusOfflineCancelsActiveOrderAndRemovesLocation(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	orderID := "order-1"
	driverRepo := newFakeDriverRepository()
	driverRepo.drivers["driver-1"] = &driverdomain.Driver{
		ID:             "driver-1",
		UserID:         "user-1",
		Status:         driverdomain.StatusBusy,
		CurrentOrderID: &orderID,
		LastSeenAt:     now,
		UpdatedAt:      now,
	}
	orderRepo := newFakeOrderRepository()
	orderRepo.orders[orderID] = &orderdomain.Order{
		ID:        orderID,
		UserID:    "client-1",
		DriverID:  strPtr("driver-1"),
		Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		Status:    orderdomain.StatusAccepted,
		CreatedAt: now,
		UpdatedAt: now,
	}
	locationRepo := &fakeLocationRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, publisher, nil, nil, fakeClock{now: now}, fakeLogger{})

	drv, err := uc.Execute(context.Background(), SetStatusInput{
		DriverID: "driver-1",
		Status:   driverdomain.StatusOffline,
	})
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if drv.Status != driverdomain.StatusOffline {
		t.Fatalf("status = %q, want %q", drv.Status, driverdomain.StatusOffline)
	}
	if orderRepo.orders[orderID].Status != orderdomain.StatusCancelled {
		t.Fatalf("order status = %q, want %q", orderRepo.orders[orderID].Status, orderdomain.StatusCancelled)
	}
	if locationRepo.removedDriverID != "driver-1" {
		t.Fatalf("removed driver = %q, want driver-1", locationRepo.removedDriverID)
	}
	if len(publisher.events) != 1 || publisher.events[0].Type != orderdomain.EventCancelled {
		t.Fatalf("events = %+v, want one cancelled event", publisher.events)
	}
}

// TestSetStatusWithCurrentOrderPublishesDriverLocation verifies the HTTP
// location bridge: whenever a driver with an active order submits a location,
// an EventDriverLocationUpdated scoped to that order's client is published.
func TestSetStatusBusyPublishesDriverLocationToOrderClient(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	orderID := "order-1"
	driverRepo := newFakeDriverRepository()
	driverRepo.drivers["driver-1"] = &driverdomain.Driver{
		ID:             "driver-1",
		UserID:         "user-1",
		Status:         driverdomain.StatusBusy,
		CurrentOrderID: &orderID,
		LastSeenAt:     now,
		UpdatedAt:      now,
	}
	orderRepo := newFakeOrderRepository()
	orderRepo.orders[orderID] = &orderdomain.Order{
		ID:        orderID,
		UserID:    "client-1",
		DriverID:  strPtr("driver-1"),
		Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		Status:    orderdomain.StatusAccepted,
		CreatedAt: now,
		UpdatedAt: now,
	}
	locationRepo := &fakeLocationRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, publisher, nil, nil, fakeClock{now: now}, fakeLogger{})

	lat := 55.755
	lng := 37.617
	if _, err := uc.Execute(context.Background(), SetStatusInput{
		DriverID: "driver-1",
		UserID:   "user-1",
		Status:   driverdomain.StatusOnline,
		Lat:      &lat,
		Lng:      &lng,
	}); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	var locEvent *orderdomain.Event
	for i := range publisher.events {
		if publisher.events[i].Type == orderdomain.EventDriverLocationUpdated {
			locEvent = &publisher.events[i]
			break
		}
	}
	if locEvent == nil {
		t.Fatalf("expected EventDriverLocationUpdated, got events: %+v", publisher.events)
	}
	if locEvent.OrderID != orderID {
		t.Fatalf("event order_id = %q, want %q", locEvent.OrderID, orderID)
	}
	payload, ok := locEvent.Payload.(map[string]any)
	if !ok {
		t.Fatalf("payload is %T, want map[string]any", locEvent.Payload)
	}
	if payload["user_id"] != "client-1" {
		t.Fatalf("payload user_id = %v, want client-1", payload["user_id"])
	}
	if payload["driver_id"] != "driver-1" {
		t.Fatalf("payload driver_id = %v, want driver-1", payload["driver_id"])
	}
}

// TestSetStatusNoCurrentOrderDoesNotPublishDriverLocation guards privacy: a
// driver that simply goes online must never emit a client location event.
func TestSetStatusNoCurrentOrderDoesNotPublishDriverLocation(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	driverRepo := newFakeDriverRepository()
	orderRepo := newFakeOrderRepository()
	locationRepo := &fakeLocationRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, publisher, nil, nil, fakeClock{now: now}, fakeLogger{})

	lat := 55.75
	lng := 37.62
	if _, err := uc.Execute(context.Background(), SetStatusInput{
		DriverID: "driver-1",
		UserID:   "user-1",
		Status:   driverdomain.StatusOnline,
		Lat:      &lat,
		Lng:      &lng,
	}); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	for _, event := range publisher.events {
		if event.Type == orderdomain.EventDriverLocationUpdated {
			t.Fatalf("unexpected EventDriverLocationUpdated for freelancer driver: %+v", event)
		}
	}
}

type fakeClock struct {
	now time.Time
}

func (c fakeClock) Now() time.Time {
	return c.now
}

type fakeLogger struct{}

func (fakeLogger) Info(string, ...any)         {}
func (fakeLogger) Error(string, error, ...any) {}

type fakeDriverRepository struct {
	drivers map[string]*driverdomain.Driver
}

func newFakeDriverRepository() *fakeDriverRepository {
	return &fakeDriverRepository{drivers: map[string]*driverdomain.Driver{}}
}

func (r *fakeDriverRepository) Upsert(_ context.Context, drv *driverdomain.Driver) error {
	copied := *drv
	r.drivers[drv.ID] = &copied
	return nil
}

func (r *fakeDriverRepository) GetByID(_ context.Context, id string) (*driverdomain.Driver, error) {
	drv, ok := r.drivers[id]
	if !ok {
		return nil, driverdomain.ErrDriverNotFound
	}
	copied := *drv
	return &copied, nil
}

func (r *fakeDriverRepository) ReleaseOrder(_ context.Context, driverID string, orderID string, now time.Time) error {
	drv, ok := r.drivers[driverID]
	if !ok {
		return driverdomain.ErrDriverNotFound
	}
	if drv.CurrentOrderID != nil && *drv.CurrentOrderID == orderID {
		drv.CurrentOrderID = nil
		drv.Status = driverdomain.StatusOnline
		drv.UpdatedAt = now
	}
	return nil
}

type fakeOrderRepository struct {
	orders map[string]*orderdomain.Order
}

func newFakeOrderRepository() *fakeOrderRepository {
	return &fakeOrderRepository{orders: map[string]*orderdomain.Order{}}
}

func (r *fakeOrderRepository) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	ord, ok := r.orders[id]
	if !ok {
		return nil, orderdomain.ErrOrderNotFound
	}
	copied := *ord
	return &copied, nil
}

func (r *fakeOrderRepository) Update(_ context.Context, ord *orderdomain.Order) error {
	if _, ok := r.orders[ord.ID]; !ok {
		return orderdomain.ErrOrderNotFound
	}
	copied := *ord
	r.orders[ord.ID] = &copied
	return nil
}

type fakeLocationRepository struct {
	savedDriverID   string
	savedLocation   location.Location
	removedDriverID string
}

func (r *fakeLocationRepository) SaveLocation(_ context.Context, driverID string, loc location.Location) error {
	r.savedDriverID = driverID
	r.savedLocation = loc
	return nil
}

func (r *fakeLocationRepository) RemoveDriver(_ context.Context, driverID string) error {
	r.removedDriverID = driverID
	return nil
}

type fakeEventPublisher struct {
	events []orderdomain.Event
}

func (p *fakeEventPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	p.events = append(p.events, event)
	return nil
}

func strPtr(value string) *string {
	return &value
}
