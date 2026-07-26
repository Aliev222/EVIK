package app

import (
	"context"
	"database/sql"
	"log"
	"sync"
	"testing"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

type fakePresenceDriverRepo struct {
	mu       sync.Mutex
	drivers  map[string]*driverdomain.Driver
	staleFn  func(olderThan time.Time, limit int) ([]*driverdomain.Driver, error)
}

func (f *fakePresenceDriverRepo) ListOnlineStale(_ context.Context, olderThan time.Time, limit int) ([]*driverdomain.Driver, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.staleFn != nil {
		return f.staleFn(olderThan, limit)
	}
	var out []*driverdomain.Driver
	for _, d := range f.drivers {
		if d.Status == driverdomain.StatusOnline && d.CurrentOrderID == nil && d.UpdatedAt.Before(olderThan) {
			out = append(out, d)
		}
	}
	return out, nil
}

func (f *fakePresenceDriverRepo) Upsert(_ context.Context, drv *driverdomain.Driver) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.drivers[drv.ID] = drv
	return nil
}

func (f *fakePresenceDriverRepo) GetByID(_ context.Context, id string) (*driverdomain.Driver, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	d, ok := f.drivers[id]
	if !ok {
		return nil, driverdomain.ErrDriverNotFound
	}
	return d, nil
}

type fakePresenceLocationStore struct {
	mu       sync.Mutex
	removed  map[string]bool
}

func (f *fakePresenceLocationStore) RemoveDriver(_ context.Context, driverID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.removed == nil {
		f.removed = make(map[string]bool)
	}
	f.removed[driverID] = true
	return nil
}

type fakePresenceEventPublisher struct {
	mu     sync.Mutex
	events []orderdomain.Event
}

func (f *fakePresenceEventPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, event)
	return nil
}

func TestDriverPresenceReaperStaleDriverGoesOffline(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	now := time.Now().UTC()
	staleDriver := &driverdomain.Driver{
		ID:         "d1",
		UserID:     "u1",
		Status:     driverdomain.StatusOnline,
		UpdatedAt:  now.Add(-5 * time.Minute),
		LastSeenAt: now.Add(-5 * time.Minute),
	}

	repo := &fakePresenceDriverRepo{
		drivers: map[string]*driverdomain.Driver{"d1": staleDriver},
	}
	locStore := &fakePresenceLocationStore{}
	eventPub := &fakePresenceEventPublisher{}

	reaper := NewDriverPresenceReaper(repo, locStore, hub, eventPub, log.Default(), 10*time.Minute, 60*time.Second)
	reaper.reapStaleDrivers(context.Background())

	repo.mu.Lock()
	updated := repo.drivers["d1"]
	repo.mu.Unlock()
	if updated == nil || updated.Status != driverdomain.StatusOffline {
		t.Fatalf("expected driver d1 to be offline, got %s", updated.Status)
	}

	locStore.mu.Lock()
	_, removed := locStore.removed["d1"]
	locStore.mu.Unlock()
	if !removed {
		t.Fatal("expected driver d1 geo entry to be removed")
	}
}

func TestDriverPresenceReaperSkipsFreshDriver(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	now := time.Now().UTC()
	freshDriver := &driverdomain.Driver{
		ID:         "d2",
		UserID:     "u2",
		Status:     driverdomain.StatusOnline,
		UpdatedAt:  now,
		LastSeenAt: now,
	}

	repo := &fakePresenceDriverRepo{
		drivers: map[string]*driverdomain.Driver{"d2": freshDriver},
	}
	locStore := &fakePresenceLocationStore{}
	eventPub := &fakePresenceEventPublisher{}

	reaper := NewDriverPresenceReaper(repo, locStore, hub, eventPub, log.Default(), 10*time.Minute, 60*time.Second)
	reaper.reapStaleDrivers(context.Background())

	repo.mu.Lock()
	updated := repo.drivers["d2"]
	repo.mu.Unlock()
	if updated.Status != driverdomain.StatusOnline {
		t.Fatalf("expected fresh driver d2 to remain online, got %s", updated.Status)
	}
	locStore.mu.Lock()
	_, removed := locStore.removed["d2"]
	locStore.mu.Unlock()
	if removed {
		t.Fatal("expected fresh driver d2 geo entry NOT to be removed")
	}
}

func TestDriverPresenceReaperSkipsDriverWithActiveOrder(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	now := time.Now().UTC()
	orderID := "order-1"
	busyDriver := &driverdomain.Driver{
		ID:             "d3",
		UserID:         "u3",
		Status:         driverdomain.StatusOnline,
		CurrentOrderID: &orderID,
		UpdatedAt:      now.Add(-10 * time.Minute),
		LastSeenAt:     now.Add(-10 * time.Minute),
	}

	repo := &fakePresenceDriverRepo{
		drivers: map[string]*driverdomain.Driver{"d3": busyDriver},
	}
	locStore := &fakePresenceLocationStore{}
	eventPub := &fakePresenceEventPublisher{}

	reaper := NewDriverPresenceReaper(repo, locStore, hub, eventPub, log.Default(), 10*time.Minute, 60*time.Second)
	reaper.reapStaleDrivers(context.Background())

	repo.mu.Lock()
	updated := repo.drivers["d3"]
	repo.mu.Unlock()
	if updated.Status == driverdomain.StatusOffline {
		t.Fatal("expected driver with active order NOT to be set offline")
	}
	locStore.mu.Lock()
	_, removed := locStore.removed["d3"]
	locStore.mu.Unlock()
	if removed {
		t.Fatal("expected driver with active order geo entry NOT to be removed")
	}
}

func TestDriverPresenceReaperSkipsDriverWithWSConnection(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	now := time.Now().UTC()
	connectedDriver := &driverdomain.Driver{
		ID:         "d4",
		UserID:     "u4",
		Status:     driverdomain.StatusOnline,
		UpdatedAt:  now.Add(-5 * time.Minute),
		LastSeenAt: now.Add(-5 * time.Minute),
	}

	hub.Register(&wsinfra.Client{UserID: "d4", Role: "driver", Send: make(chan []byte, 10)})
	waitHubDriver(t, hub, "d4")

	repo := &fakePresenceDriverRepo{
		drivers: map[string]*driverdomain.Driver{"d4": connectedDriver},
	}
	locStore := &fakePresenceLocationStore{}
	eventPub := &fakePresenceEventPublisher{}

	reaper := NewDriverPresenceReaper(repo, locStore, hub, eventPub, log.Default(), 10*time.Minute, 60*time.Second)
	reaper.reapStaleDrivers(context.Background())

	repo.mu.Lock()
	updated := repo.drivers["d4"]
	repo.mu.Unlock()
	if updated.Status != driverdomain.StatusOnline {
		t.Fatalf("expected driver with WS connection to remain online, got %s", updated.Status)
	}
}

// Stub implementations for StuckOrderReaper tests

type fakeStuckOrderRepo struct {
	mu     sync.Mutex
	orders map[string]*orderdomain.Order
}

func (f *fakeStuckOrderRepo) ListByStatus(_ context.Context, status orderdomain.Status, limit int) ([]*orderdomain.Order, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []*orderdomain.Order
	for _, ord := range f.orders {
		if ord.Status == status {
			out = append(out, ord)
		}
	}
	return out, nil
}

func (f *fakeStuckOrderRepo) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	ord, ok := f.orders[id]
	if !ok {
		return nil, orderdomain.ErrOrderNotFound
	}
	return ord, nil
}

func (f *fakeStuckOrderRepo) Update(_ context.Context, ord *orderdomain.Order) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.orders[ord.ID] = ord
	return nil
}

func (f *fakeStuckOrderRepo) UpdateTx(_ context.Context, tx *sql.Tx, ord *orderdomain.Order) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.orders[ord.ID] = ord
	return nil
}

type fakeStuckDriverRepo struct {
	mu      sync.Mutex
	drivers map[string]*driverdomain.Driver
}

func (f *fakeStuckDriverRepo) GetByID(_ context.Context, id string) (*driverdomain.Driver, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	d, ok := f.drivers[id]
	if !ok {
		return nil, driverdomain.ErrDriverNotFound
	}
	return d, nil
}

func (f *fakeStuckDriverRepo) ReleaseOrderTx(_ context.Context, tx *sql.Tx, driverID string, orderID string, now time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	d, ok := f.drivers[driverID]
	if !ok {
		return driverdomain.ErrDriverNotFound
	}
	d.Status = driverdomain.StatusOnline
	d.CurrentOrderID = nil
	d.UpdatedAt = now
	return nil
}

type fakeStuckEventPublisher struct {
	mu     sync.Mutex
	events []orderdomain.Event
}

func (f *fakeStuckEventPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, event)
	return nil
}

func TestStuckOrderReaperSearchingTimedOut(t *testing.T) {
	now := time.Now().UTC()
	expandedAt := now.Add(-10 * time.Minute)
	ord := &orderdomain.Order{
		ID:         "o1",
		Status:     orderdomain.StatusSearching,
		IsExpanded: true,
		ExpandedAt: &expandedAt,
		UpdatedAt:  now.Add(-10 * time.Minute),
		CreatedAt:  now.Add(-15 * time.Minute),
	}

	orderRepo := &fakeStuckOrderRepo{orders: map[string]*orderdomain.Order{"o1": ord}}
	driverRepo := &fakeStuckDriverRepo{drivers: map[string]*driverdomain.Driver{}}
	eventPub := &fakeStuckEventPublisher{}

	reaper := NewStuckOrderReaper(nil, orderRepo, driverRepo, eventPub, log.Default(),
		30*time.Second, 5*time.Minute, 15*time.Minute, 2*time.Hour, 4*time.Hour, 24*time.Hour, "cancel")

	reaper.reapStuckOrders(context.Background())

	if ord.Status != orderdomain.StatusNoDriverFound {
		t.Fatalf("expected order o1 to be no_driver_found, got %s", ord.Status)
	}

	found := false
	for _, e := range eventPub.events {
		if e.Type == orderdomain.EventNoDriverFound && e.OrderID == "o1" {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("expected EventNoDriverFound published for o1")
	}
}

func TestStuckOrderReaperSearchingNotExpandedSkipped(t *testing.T) {
	now := time.Now().UTC()
	ord := &orderdomain.Order{
		ID:         "o2",
		Status:     orderdomain.StatusSearching,
		IsExpanded: false,
		UpdatedAt:  now.Add(-30 * time.Minute),
		CreatedAt:  now.Add(-35 * time.Minute),
	}

	orderRepo := &fakeStuckOrderRepo{orders: map[string]*orderdomain.Order{"o2": ord}}
	driverRepo := &fakeStuckDriverRepo{}
	eventPub := &fakeStuckEventPublisher{}

	reaper := NewStuckOrderReaper(nil, orderRepo, driverRepo, eventPub, log.Default(),
		30*time.Second, 5*time.Minute, 15*time.Minute, 2*time.Hour, 4*time.Hour, 24*time.Hour, "cancel")

	reaper.reapStuckOrders(context.Background())

	if ord.Status != orderdomain.StatusSearching {
		t.Fatalf("expected non-expanded order to remain searching, got %s", ord.Status)
	}
}

func TestStuckOrderReaperAcceptedTimedOutCancelAndRelease(t *testing.T) {
	now := time.Now().UTC()
	driverID := "d-rel"
	ord := &orderdomain.Order{
		ID:        "o3",
		Status:    orderdomain.StatusAccepted,
		DriverID:  &driverID,
		UpdatedAt: now.Add(-20 * time.Minute),
		CreatedAt: now.Add(-25 * time.Minute),
	}
	drv := &driverdomain.Driver{
		ID:             driverID,
		Status:         driverdomain.StatusBusy,
		CurrentOrderID: &ord.ID,
		UpdatedAt:      now.Add(-20 * time.Minute),
	}

	orderRepo := &fakeStuckOrderRepo{orders: map[string]*orderdomain.Order{"o3": ord}}
	driverRepo := &fakeStuckDriverRepo{drivers: map[string]*driverdomain.Driver{driverID: drv}}
	eventPub := &fakeStuckEventPublisher{}

	reaper := NewStuckOrderReaper(nil, orderRepo, driverRepo, eventPub, log.Default(),
		30*time.Second, 5*time.Minute, 15*time.Minute, 2*time.Hour, 4*time.Hour, 24*time.Hour, "cancel")

	reaper.reapStuckOrders(context.Background())

	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("expected order o3 to be cancelled, got %s", ord.Status)
	}
	if drv.Status != driverdomain.StatusOnline {
		t.Fatalf("expected driver %s to be released (online), got %s", driverID, drv.Status)
	}
	if drv.CurrentOrderID != nil {
		t.Fatal("expected driver current_order_id to be nil after release")
	}

	found := false
	for _, e := range eventPub.events {
		if e.Type == orderdomain.EventCancelled && e.OrderID == "o3" {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("expected EventCancelled published for o3")
	}
}

func TestStuckOrderReaperHealthyOrderNoop(t *testing.T) {
	now := time.Now().UTC()
	driverID := "d-healthy"

	acceptedOrder := &orderdomain.Order{
		ID:        "o4",
		Status:    orderdomain.StatusAccepted,
		DriverID:  &driverID,
		UpdatedAt: now.Add(-2 * time.Minute),
		CreatedAt: now.Add(-5 * time.Minute),
	}
	searchingOrder := &orderdomain.Order{
		ID:         "o5",
		Status:     orderdomain.StatusSearching,
		IsExpanded: true,
		UpdatedAt:  now.Add(-2 * time.Minute),
		CreatedAt:  now.Add(-5 * time.Minute),
	}
	inProgressOrder := &orderdomain.Order{
		ID:        "o6",
		Status:    orderdomain.StatusInProgress,
		DriverID:  &driverID,
		UpdatedAt: now.Add(-30 * time.Minute),
		CreatedAt: now.Add(-2 * time.Hour),
	}

	orderRepo := &fakeStuckOrderRepo{
		orders: map[string]*orderdomain.Order{
			"o4": acceptedOrder,
			"o5": searchingOrder,
			"o6": inProgressOrder,
		},
	}
	driverRepo := &fakeStuckDriverRepo{}
	eventPub := &fakeStuckEventPublisher{}

	reaper := NewStuckOrderReaper(nil, orderRepo, driverRepo, eventPub, log.Default(),
		30*time.Second, 5*time.Minute, 15*time.Minute, 2*time.Hour, 4*time.Hour, 24*time.Hour, "cancel")

	reaper.reapStuckOrders(context.Background())

	if acceptedOrder.Status != orderdomain.StatusAccepted {
		t.Fatalf("expected accepted order to stay accepted, got %s", acceptedOrder.Status)
	}
	if searchingOrder.Status != orderdomain.StatusSearching {
		t.Fatalf("expected searching order to stay searching, got %s", searchingOrder.Status)
	}
	if inProgressOrder.Status != orderdomain.StatusInProgress {
		t.Fatalf("expected in_progress order to stay in_progress, got %s", inProgressOrder.Status)
	}
}
