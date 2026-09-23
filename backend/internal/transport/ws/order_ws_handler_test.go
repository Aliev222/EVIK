package ws

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"testing"
	"time"

	chatdomain "evik/backend/internal/domain/chat"
	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

type fakeLocationRepo struct {
	savedDriverID string
	savedLoc      location.Location
}

type fakeWSChatRepo struct {
	sender  string
	allow   bool
	message chatdomain.Message
}

func (r *fakeWSChatRepo) CanAccess(context.Context, string, string) (bool, error) {
	return r.allow, nil
}
func (r *fakeWSChatRepo) Create(_ context.Context, orderID, sender, clientID, text string) (chatdomain.Message, error) {
	if !r.allow {
		return chatdomain.Message{}, chatdomain.ErrForbidden
	}
	r.sender = sender
	r.message = chatdomain.Message{ID: "m1", OrderID: orderID, SenderID: sender, ClientMessageID: clientID, Text: text}
	return r.message, nil
}
func (r *fakeWSChatRepo) List(context.Context, string, string, string, int) ([]chatdomain.Message, error) {
	return nil, nil
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
		"lat":      lat,
		"lng":      lng,
		"bearing":  90.0,
		"speed":    42.0,
		"status":   "to_pickup",
		"order_id": orderID,
		"is_mock":  false,
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

func TestWSChatSendPersistsBeforeAcknowledgementAndUsesSocketIdentity(t *testing.T) {
	handler, _, _, publisher, _ := newTestHandler()
	chatRepo := &fakeWSChatRepo{allow: true}
	handler.SetChatRepository(chatRepo)
	client := &wsinfra.Client{UserID: "client-1", Role: "client", Send: make(chan []byte, 1)}
	handler.handleWSMessage(client, []byte(`{"type":"chat.send","data":{"order_id":"o1","client_message_id":"retry-1","text":"Где вы?","sender_id":"driver-1"}}`))
	if chatRepo.sender != "client-1" {
		t.Fatalf("sender=%q, want authenticated socket user", chatRepo.sender)
	}
	if len(publisher.events) != 1 || publisher.events[0].Type != orderdomain.EventChatMessage {
		t.Fatalf("events=%+v", publisher.events)
	}
	select {
	case ack := <-client.Send:
		var frame map[string]any
		if err := json.Unmarshal(ack, &frame); err != nil || frame["type"] != "chat.ack" {
			t.Fatalf("ack=%s", ack)
		}
	default:
		t.Fatal("missing saved acknowledgement")
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

// Small GPS movements are still live-order telemetry.  The 50 m geo-index
// optimisation must not make the client wait for a large jump on the map.
func TestWSHandleLocationUpdatePublishesSmallMovement(t *testing.T) {
	handler, _, orderRepo, publisher, clock := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{ID: orderID, UserID: "client-1", DriverID: strPtr("driver-1"), Status: orderdomain.StatusAccepted}
	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}

	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755000, 37.617000))
	clock.now = clock.now.Add(3 * time.Second)
	// ~11 m north: deliberately below the geo-index threshold.
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755100, 37.617000))

	if got := len(publisher.events); got != 2 {
		t.Fatalf("events = %d, want 2 live client updates", got)
	}
}

func TestWSHandleLocationUpdateRejectsRepeatedOrOlderSample(t *testing.T) {
	handler, _, orderRepo, publisher, clock := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{ID: orderID, UserID: "client-1", DriverID: strPtr("driver-1"), Status: orderdomain.StatusAccepted}
	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}
	sampledAt := clock.now.Add(-time.Second).UTC().Format(time.RFC3339Nano)
	// Use the real frame shape because sampled_at is part of the driver data,
	// not a server timestamp.
	data, _ := json.Marshal(map[string]any{"lat": 55.755, "lng": 37.617, "order_id": orderID, "sampled_at": sampledAt})
	frame, _ := json.Marshal(map[string]any{"type": "location_update", "driver_id": "driver-1", "data": json.RawMessage(data)})
	handler.handleLocationUpdate(client, frame)
	clock.now = clock.now.Add(3 * time.Second)
	handler.handleLocationUpdate(client, frame)
	if got := len(publisher.events); got != 1 {
		t.Fatalf("events = %d, want 1 after repeated sampled_at", got)
	}
}

func TestWSHandleLocationUpdateRejectsSingleGPSOutlier(t *testing.T) {
	handler, _, orderRepo, publisher, clock := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{ID: orderID, UserID: "client-1", DriverID: strPtr("driver-1"), Status: orderdomain.StatusAccepted}
	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}

	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))
	clock.now = clock.now.Add(3 * time.Second)
	// More than 10 km in three seconds: reject without poisoning the last good
	// sample, so the following legitimate point can still be accepted.
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.855, 37.817))
	clock.now = clock.now.Add(3 * time.Second)
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.7551, 37.617))

	if got := len(publisher.events); got != 2 {
		t.Fatalf("events = %d, want first and recovered valid point only", got)
	}
	payload := publisher.events[1].Payload.(map[string]any)
	if payload["lat"] != 55.7551 {
		t.Fatalf("recovered latitude = %v, want 55.7551", payload["lat"])
	}
}

// A stationary vehicle still needs periodic freshness for a truthful client
// state (and phase changes must not be hidden by a distance filter).
func TestWSHandleLocationUpdatePublishesStationaryFreshness(t *testing.T) {
	handler, _, orderRepo, publisher, clock := newTestHandler()
	orderID := "order-1"
	orderRepo.orders[orderID] = &orderdomain.Order{ID: orderID, UserID: "client-1", DriverID: strPtr("driver-1"), Status: orderdomain.StatusAccepted}
	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}

	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))
	clock.now = clock.now.Add(31 * time.Second)
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))

	if got := len(publisher.events); got != 2 {
		t.Fatalf("events = %d, want 2 stationary freshness updates", got)
	}
	payload := publisher.events[1].Payload.(map[string]any)
	if payload["sampled_at"] == "" || payload["received_at"] == "" {
		t.Fatalf("timestamps missing from telemetry payload: %+v", payload)
	}
}

func TestWSHandleLocationUpdateUsesAuthoritativeOrderPhase(t *testing.T) {
	handler, _, orderRepo, publisher, clock := newTestHandler()
	orderID := "order-1"
	order := &orderdomain.Order{ID: orderID, UserID: "client-1", DriverID: strPtr("driver-1"), Status: orderdomain.StatusAccepted}
	orderRepo.orders[orderID] = order
	client := &wsinfra.Client{UserID: "driver-1", Role: "driver"}

	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))
	order.Status = orderdomain.StatusInProgress
	// A state transition is relevant even when its accompanying GPS sample is
	// within the usual two-second event throttle.
	clock.now = clock.now.Add(time.Second)
	handler.handleLocationUpdate(client, driverWSMessage("driver-1", orderID, 55.755, 37.617))

	if got := len(publisher.events); got != 2 {
		t.Fatalf("events = %d, want phase transition to publish", got)
	}
	payload := publisher.events[1].Payload.(map[string]any)
	if payload["status"] != "to_destination" {
		t.Fatalf("status = %v, want to_destination", payload["status"])
	}
}
