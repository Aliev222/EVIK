package ws

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"testing"
	"time"

	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

type fakeLocationRepo struct {
	savedDriverID string
	savedLoc      location.Location
}

func (r *fakeLocationRepo) SaveLocation(_ context.Context, driverID string, loc location.Location) error {
	r.savedDriverID = driverID
	r.savedLoc = loc
	return nil
}

type fakeOrderRepo struct {
	orders map[string]*orderdomain.Order
}

func newFakeOrderRepo() *fakeOrderRepo {
	return &fakeOrderRepo{orders: map[string]*orderdomain.Order{}}
}

func (r *fakeOrderRepo) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	ord, ok := r.orders[id]
	if !ok {
		return nil, orderdomain.ErrOrderNotFound
	}
	return ord, nil
}

type fakeEventPublisher struct {
	events []orderdomain.Event
}

func (p *fakeEventPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	p.events = append(p.events, event)
	return nil
}

// mutableClock lets tests advance the 2s location throttle in steps.
type mutableClock struct {
	now time.Time
}

func (c *mutableClock) Now() time.Time {
	return c.now
}

func newTestHandler() (
	*OrderWSHandler,
	*fakeLocationRepo,
	*fakeOrderRepo,
	*fakeEventPublisher,
	*mutableClock,
) {
	clock := &mutableClock{now: time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)}
	locationRepo := &fakeLocationRepo{}
	orderRepo := newFakeOrderRepo()
	publisher := &fakeEventPublisher{}
	handler := NewOrderWSHandler(nil, nil, log.New(os.Stderr, "test", 0), nil, locationRepo, orderRepo, publisher, clock.Now)
	return handler, locationRepo, orderRepo, publisher, clock
}

func driverWSMessage(driverID, orderID string, lat, lng float64) []byte {
	data, _ := json.Marshal(map[string]any{
		"lat":     lat,
		"lng":     lng,
		"bearing": 90.0,
		"speed":   42.0,
		"status":  "to_pickup",
		"order_id": orderID,
		"is_mock": false,
	})
	msg, _ := json.Marshal(map[string]any{
		"type":      "location_update",
		"driver_id": driverID,
		"data":      json.RawMessage(data),
	})
	return msg
}

func strPtr(value string) *string {
	return &value
}

// TestWSHandleLocationUpdatePublishesToOrderClient verifies the WS path
// publishes a driver_location event for the order's own client when the
// assigned driver reports a position.
func TestWSHandleLocationUpdatePublishesToOrderClient(t *testing.T) {
	handler, locationRepo, orderRepo, publisher, _ := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{
		ID:       orderID,
		UserID:   "client-1",
		DriverID: strPtr("driver-1"),
		Status:   orderdomain.StatusAccepted,
	}

	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))

	if locationRepo.savedDriverID != "driver-1" {
		t.Fatalf("saved driver = %q, want driver-1", locationRepo.savedDriverID)
	}
	if len(publisher.events) != 1 {
		t.Fatalf("events = %+v, want exactly one", publisher.events)
	}
	event := publisher.events[0]
	if event.Type != orderdomain.EventDriverLocationUpdated {
		t.Fatalf("event type = %q, want %q", event.Type, orderdomain.EventDriverLocationUpdated)
	}
	if event.OrderID != orderID {
		t.Fatalf("event order_id = %q, want %q", event.OrderID, orderID)
	}
	payload := event.Payload.(map[string]any)
	if payload["user_id"] != "client-1" {
		t.Fatalf("payload user_id = %v, want client-1", payload["user_id"])
	}
	if payload["driver_id"] != "driver-1" {
		t.Fatalf("payload driver_id = %v, want driver-1", payload["driver_id"])
	}
}

// TestWSHandleLocationUpdateWithoutOrderDoesNotPublish guards the freelancer
// case: location without an active order must never reach a client.
func TestWSHandleLocationUpdateWithoutOrderDoesNotPublish(t *testing.T) {
	handler, _, _, publisher, _ := newTestHandler()

	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", "", 55.755, 37.617))

	for _, event := range publisher.events {
		if event.Type == orderdomain.EventDriverLocationUpdated {
			t.Fatalf("unexpected driver_location event without an order: %+v", event)
		}
	}
}

// TestWSHandleLocationUpdateForeignOrderDoesNotPublish verifies a driver can't
// push their location to a client of an order they are not assigned to.
func TestWSHandleLocationUpdateForeignOrderDoesNotPublish(t *testing.T) {
	handler, _, orderRepo, publisher, _ := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{
		ID:       orderID,
		UserID:   "client-1",
		DriverID: strPtr("other-driver"),
		Status:   orderdomain.StatusAccepted,
	}

	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))

	if len(publisher.events) != 0 {
		t.Fatalf("events = %+v, want none for foreign order", publisher.events)
	}
}

// TestWSHandleLocationUpdateRejectsClientRole ensures a client WebSocket can't
// publish location events.
func TestWSHandleLocationUpdateRejectsClientRole(t *testing.T) {
	handler, _, orderRepo, publisher, _ := newTestHandler()
	orderRepo.orders["order-1"] = &orderdomain.Order{
		ID:       "order-1",
		UserID:   "client-1",
		DriverID: strPtr("driver-1"),
		Status:   orderdomain.StatusAccepted,
	}

	client := &wsinfra.Client{UserID: "client-1", Role: "client"}
	handler.handleLocationUpdate(client, driverWSMessage("client-1", "order-1", 55.755, 37.617))

	if len(publisher.events) != 0 {
		t.Fatalf("events = %+v, want none from a client", publisher.events)
	}
}

// TestWSHandleLocationUpdateThrottle verifies at most one event per 2s window
// reaches the client.
func TestWSHandleLocationUpdateThrottle(t *testing.T) {
	handler, _, orderRepo, publisher, clock := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{
		ID:       orderID,
		UserID:   "client-1",
		DriverID: strPtr("driver-1"),
		Status:   orderdomain.StatusAccepted,
	}

	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))
	clock.now = clock.now.Add(500 * time.Millisecond)
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.756, 37.618))
	clock.now = clock.now.Add(2 * time.Second)
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.757, 37.619))

	if len(publisher.events) != 2 {
		t.Fatalf("events = %+v, want 2 (throttled mid-window update)", publisher.events)
	}
}