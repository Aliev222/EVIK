package order

import (
	"context"
	"database/sql"
	"errors"
	"sync"
	"testing"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
)

func TestAcceptOrderRejectsUnavailableDriver(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
			Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:    orderdomain.StatusSearching,
			CreatedAt: now,
			UpdatedAt: now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{assignErr: driverdomain.ErrDriverBusy}
	publisher := &fakeEventPublisher{}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, nil, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	_, err := uc.Execute(context.Background(), "order-1", "driver-1")
	if !errors.Is(err, driverdomain.ErrDriverBusy) {
		t.Fatalf("error = %v, want ErrDriverBusy", err)
	}
	if orderRepo.updated {
		t.Fatal("order was updated for unavailable driver")
	}
	if len(publisher.Events()) != 0 {
		t.Fatalf("events = %+v, want none", publisher.Events())
	}
}

func TestAcceptOrderAssignsDriverAndPublishesEvent(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
			Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:    orderdomain.StatusSearching,
			CreatedAt: now,
			UpdatedAt: now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, nil, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", "driver-1")
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusAccepted {
		t.Fatalf("status = %q, want %q", ord.Status, orderdomain.StatusAccepted)
	}
	if ord.DriverID == nil || *ord.DriverID != "driver-1" {
		t.Fatalf("driver id = %v, want driver-1", ord.DriverID)
	}
	if !driverRepo.assigned {
		t.Fatal("driver was not assigned")
	}
	if evs := publisher.Events(); len(evs) != 1 || evs[0].Type != orderdomain.EventAccepted {
		t.Fatalf("events = %+v, want one accepted event", evs)
	}
}

func TestAcceptOrderIsIdempotentForSameDriverActiveOrder(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	for _, status := range []orderdomain.Status{
		orderdomain.StatusAccepted,
		orderdomain.StatusArrived,
		orderdomain.StatusInProgress,
	} {
		t.Run(string(status), func(t *testing.T) {
			driverID := "driver-1"
			orderRepo := &fakeOrderRepository{
				order: &orderdomain.Order{
					ID:        "order-1",
					UserID:    "client-1",
					DriverID:  &driverID,
					Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
					Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
					Status:    status,
					CreatedAt: now,
					UpdatedAt: now,
				},
			}
			driverRepo := &fakeDriverOrderRepository{}
			publisher := &fakeEventPublisher{}
			uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, nil, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

			ord, err := uc.Execute(context.Background(), "order-1", driverID)
			if err != nil {
				t.Fatalf("Execute returned error: %v", err)
			}
			if ord.Status != status {
				t.Fatalf("status = %q, want %q", ord.Status, status)
			}
			if ord.DriverID == nil || *ord.DriverID != driverID {
				t.Fatalf("driver id = %v, want %s", ord.DriverID, driverID)
			}
			if orderRepo.updated {
				t.Fatal("order was updated for idempotent accept")
			}
			if driverRepo.assignCalls != 0 {
				t.Fatalf("assign calls = %d, want 0", driverRepo.assignCalls)
			}
			if len(publisher.Events()) != 0 {
				t.Fatalf("events = %+v, want none", publisher.Events())
			}
		})
	}
}

func TestAcceptOrderRecoversStaleTerminalDriverOrderAndRetries(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	staleID := "order-stale"
	targetID := "order-1"
	orderRepo := &fakeOrderRepository{
		orders: map[string]*orderdomain.Order{
			targetID: {
				ID:        targetID,
				UserID:    "client-1",
				Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				Status:    orderdomain.StatusSearching,
				CreatedAt: now,
				UpdatedAt: now,
			},
			staleID: {
				ID:        staleID,
				UserID:    "client-2",
				Pickup:    orderdomain.Coordinate{Lat: 55.70, Lng: 37.60},
				Dropoff:   orderdomain.Coordinate{Lat: 55.71, Lng: 37.61},
				Status:    orderdomain.StatusCancelled,
				CreatedAt: now,
				UpdatedAt: now,
			},
		},
	}
	driverRepo := &fakeDriverOrderRepository{
		assignErrSequence: []error{driverdomain.ErrDriverBusy, nil},
		driver: &driverdomain.Driver{
			ID:             "driver-1",
			Status:         driverdomain.StatusBusy,
			CurrentOrderID: &staleID,
			LastSeenAt:     now,
			UpdatedAt:      now,
		},
	}
	publisher := &fakeEventPublisher{}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, nil, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), targetID, "driver-1")
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusAccepted {
		t.Fatalf("status = %q, want %q", ord.Status, orderdomain.StatusAccepted)
	}
	if driverRepo.assignCalls != 2 {
		t.Fatalf("assign calls = %d, want 2", driverRepo.assignCalls)
	}
	if len(driverRepo.releasedOrders) != 1 || driverRepo.releasedOrders[0] != staleID {
		t.Fatalf("released orders = %+v, want [%s]", driverRepo.releasedOrders, staleID)
	}
}

// TestAcceptOrderRecoveryUsesDriverAndTargetOrderIDs guards against the
// B-06.x argument swap where tryRecoverAndRetry was called as
// (orderID, driverID) instead of (driverID, orderID). With the swapped order
// the driver repo would be looked up by the target order id, recovery would
// silently fail and the accept would surface ErrDriverBusy instead of
// succeeding.
func TestAcceptOrderRecoveryUsesDriverAndTargetOrderIDs(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	staleID := "order-stale"
	targetID := "order-1"
	orderRepo := &fakeOrderRepository{
		orders: map[string]*orderdomain.Order{
			targetID: {
				ID:        targetID,
				UserID:    "client-1",
				Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				Status:    orderdomain.StatusSearching,
				CreatedAt: now,
				UpdatedAt: now,
			},
			staleID: {
				ID:        staleID,
				UserID:    "client-2",
				Pickup:    orderdomain.Coordinate{Lat: 55.70, Lng: 37.60},
				Dropoff:   orderdomain.Coordinate{Lat: 55.71, Lng: 37.61},
				Status:    orderdomain.StatusCancelled,
				CreatedAt: now,
				UpdatedAt: now,
			},
		},
	}
	driverRepo := &fakeDriverOrderRepository{
		assignErrSequence: []error{driverdomain.ErrDriverBusy, nil},
		driver: &driverdomain.Driver{
			ID:             "driver-1",
			Status:         driverdomain.StatusBusy,
			CurrentOrderID: &staleID,
			LastSeenAt:     now,
			UpdatedAt:      now,
		},
	}
	publisher := &fakeEventPublisher{}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, nil, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	if _, err := uc.Execute(context.Background(), targetID, "driver-1"); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	// The driver repo must be queried by the driver id, never by an order id.
	if len(driverRepo.getByIDCalls) == 0 {
		t.Fatal("recovery did not query the driver repository")
	}
	for _, id := range driverRepo.getByIDCalls {
		if id == targetID {
			t.Fatalf("driver repository queried with target order id %q instead of driver id", id)
		}
	}
	// The released order must be the stale driver current order, not the target.
	if len(driverRepo.releasedOrders) != 1 || driverRepo.releasedOrders[0] != staleID {
		t.Fatalf("released orders = %+v, want [%s]", driverRepo.releasedOrders, staleID)
	}
}


func TestAcceptOrderReusesSameDriverCurrentOrderOnUnavailable(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	targetID := "order-1"
	orderRepo := &fakeOrderRepository{
		orders: map[string]*orderdomain.Order{
			targetID: {
				ID:        targetID,
				UserID:    "client-1",
				Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				Status:    orderdomain.StatusSearching,
				CreatedAt: now,
				UpdatedAt: now,
			},
		},
	}
	driverRepo := &fakeDriverOrderRepository{
		assignErr: driverdomain.ErrDriverBusy,
		driver: &driverdomain.Driver{
			ID:             "driver-1",
			Status:         driverdomain.StatusBusy,
			CurrentOrderID: &targetID,
			LastSeenAt:     now,
			UpdatedAt:      now,
		},
	}
	publisher := &fakeEventPublisher{}
	uc := NewAcceptOrderUseCase(nil, orderRepo, driverRepo, nil, nil, nil, nil, publisher, nil, fakeClock{now: now}, fakeLogger{})

	_, err := uc.Execute(context.Background(), targetID, "driver-1")
	if !errors.Is(err, driverdomain.ErrDriverBusy) {
		t.Fatalf("error = %v, want ErrDriverBusy", err)
	}
}

type orderSnapshot struct {
	Status   orderdomain.Status
	DriverID *string
}

type fakeOrderRepository struct {
	order          *orderdomain.Order
	orders         map[string]*orderdomain.Order
	updated        bool
	getByKeyOrders map[string]*orderdomain.Order
	savedSnapshots map[string]*orderSnapshot
}

func (r *fakeOrderRepository) AcceptOrder(_ context.Context, orderID, driverID string) (*orderdomain.Order, error) {
	ord, err := r.GetByID(context.Background(), orderID)
	if err != nil {
		return nil, err
	}
	if ord.Status != orderdomain.StatusSearching || ord.DriverID != nil {
		return nil, orderdomain.ErrOrderAlreadyTaken
	}
	ord.DriverID = &driverID
	ord.Status = orderdomain.StatusAccepted
	if r.orders != nil {
		r.orders[orderID] = ord
	} else {
		r.order = ord
	}
	copied := *ord
	return &copied, nil
}

func (r *fakeOrderRepository) Create(ctx context.Context, ord *orderdomain.Order) error {
	if ord.IdempotencyKey != nil && *ord.IdempotencyKey != "" {
		if existing, ok := r.getOrderByKey(*ord.IdempotencyKey); ok {
			ord.ID = existing.ID
			return orderdomain.ErrIdempotencyConflict
		}
		r.getByKeyOrders[*ord.IdempotencyKey] = ord
	}
	if r.orders != nil {
		r.orders[ord.ID] = ord
	} else {
		r.order = ord
	}
	return nil
}

func (r *fakeOrderRepository) getOrderByKey(idempotencyKey string) (*orderdomain.Order, bool) {
	if r.getByKeyOrders != nil {
		if ord, ok := r.getByKeyOrders[idempotencyKey]; ok {
			copied := *ord
			return &copied, true
		}
	}
	return nil, false
}

func (r *fakeOrderRepository) UpdateStatus(_ context.Context, id string, status orderdomain.Status, updatedAt time.Time) error {
	ord, err := r.GetByID(context.Background(), id)
	if err != nil {
		return err
	}
	ord.Status = status
	ord.UpdatedAt = updatedAt
	return nil
}

func (r *fakeOrderRepository) Update(_ context.Context, ord *orderdomain.Order) error {
	copied := *ord
	r.order = &copied
	if r.orders != nil {
		r.orders[ord.ID] = &copied
	}
	r.updated = true
	return nil
}

func (r *fakeOrderRepository) AcceptOrderTx(_ context.Context, _ *sql.Tx, orderID, driverID string) (*orderdomain.Order, error) {
	// If this is a tx retry and the order is already accepted, simulate a
	// rollback by restoring the original state saved by the first call.
	if r.orders != nil {
		if ord, ok := r.orders[orderID]; ok && ord.Status == orderdomain.StatusAccepted && ord.DriverID != nil {
			if snap, ok := r.savedSnapshots[orderID]; ok {
				r.orders[orderID] = &orderdomain.Order{
					ID: orderID, Status: snap.Status, DriverID: snap.DriverID,
				}
			}
		}
	}
	ord, err := r.AcceptOrder(context.Background(), orderID, driverID)
	if err == nil && r.savedSnapshots == nil {
		r.savedSnapshots = make(map[string]*orderSnapshot)
	}
	if err == nil {
		r.savedSnapshots[orderID] = &orderSnapshot{Status: orderdomain.StatusSearching, DriverID: nil}
	}
	return ord, err
}

// CancelOrder atomically simulates the single-statement conditional update of
// the real repository: only live (non-completed/non-cancelled) orders match,
// the current driver_id is preserved on the row, and cancelled_at/cancel_reason
// are stamped. Returns ErrOrderNotFound when the order is already terminal.
func (r *fakeOrderRepository) CancelOrder(_ context.Context, orderID string, reason string, now time.Time) (*orderdomain.Order, error) {
	ord, err := r.GetByID(context.Background(), orderID)
	if err != nil {
		return nil, err
	}
	if !cancellableByFake(ord.Status) {
		return nil, orderdomain.ErrOrderNotFound
	}
	ord.Status = orderdomain.StatusCancelled
	ord.CancelledAt = &now
	ord.UpdatedAt = now
	ord.CancelReason = reason
	r.updated = true
	if r.orders != nil {
		r.orders[orderID] = ord
	} else {
		r.order = ord
	}
	copied := *ord
	return &copied, nil
}

// cancellableByFake mirrors the repository's WHERE clause: any status other
// than completed/cancelled may be cancelled.
func cancellableByFake(status orderdomain.Status) bool {
	return status != orderdomain.StatusCompleted && status != orderdomain.StatusCancelled
}

func (r *fakeOrderRepository) UpdateTx(_ context.Context, _ *sql.Tx, ord *orderdomain.Order) error {
	return r.Update(context.Background(), ord)
}

func (r *fakeOrderRepository) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	if r.orders != nil {
		if ord, ok := r.orders[id]; ok {
			copied := *ord
			return &copied, nil
		}
		return nil, orderdomain.ErrOrderNotFound
	}
	if r.order == nil || r.order.ID != id {
		return nil, orderdomain.ErrOrderNotFound
	}
	copied := *r.order
	return &copied, nil
}

func (r *fakeOrderRepository) GetByOrderKey(_ context.Context, idempotencyKey string) (*orderdomain.Order, error) {
	if ord, ok := r.getOrderByKey(idempotencyKey); ok {
		return ord, nil
	}
	return nil, orderdomain.ErrOrderNotFound
}

func (r *fakeOrderRepository) ListByStatus(context.Context, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}

func (r *fakeOrderRepository) ListAdminOrders(context.Context, orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error) {
	return nil, 0, nil
}

func (r *fakeOrderRepository) GetAdminOrderDetails(context.Context, string) (*orderdomain.AdminOrderDetails, error) {
	return nil, nil
}

type fakeDriverOrderRepository struct {
	assignErr         error
	assignErrSequence []error
	assigned          bool
	released          bool
	assignCalls       int
	releasedOrders    []string
	getByIDCalls      []string
	driver            *driverdomain.Driver
	getByIDErr        error
}

func (r *fakeDriverOrderRepository) AssignOrder(_ context.Context, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error) {
	r.assignCalls++
	if len(r.assignErrSequence) > 0 {
		idx := r.assignCalls - 1
		if idx >= 0 && idx < len(r.assignErrSequence) && r.assignErrSequence[idx] != nil {
			return nil, r.assignErrSequence[idx]
		}
	}
	if r.assignErr != nil {
		return nil, r.assignErr
	}
	r.assigned = true
	r.driver = &driverdomain.Driver{
		ID:             driverID,
		Status:         driverdomain.StatusBusy,
		CurrentOrderID: &orderID,
		LastSeenAt:     now,
		UpdatedAt:      now,
	}
	return &driverdomain.Driver{
		ID:             driverID,
		Status:         driverdomain.StatusBusy,
		CurrentOrderID: &orderID,
		LastSeenAt:     now,
		UpdatedAt:      now,
	}, nil
}

func (r *fakeDriverOrderRepository) AssignOrderTx(_ context.Context, _ *sql.Tx, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error) {
	return r.AssignOrder(context.Background(), driverID, orderID, now)
}

func (r *fakeDriverOrderRepository) ReleaseOrder(_ context.Context, driverID string, orderID string, now time.Time) error {
	r.released = true
	r.releasedOrders = append(r.releasedOrders, orderID)
	if r.driver != nil && r.driver.ID == driverID && r.driver.CurrentOrderID != nil && *r.driver.CurrentOrderID == orderID {
		r.driver.CurrentOrderID = nil
		r.driver.Status = driverdomain.StatusOnline
		r.driver.UpdatedAt = now
	}
	return nil
}

func (r *fakeDriverOrderRepository) GetByID(_ context.Context, id string) (*driverdomain.Driver, error) {
	r.getByIDCalls = append(r.getByIDCalls, id)
	if r.getByIDErr != nil {
		return nil, r.getByIDErr
	}
	if r.driver == nil {
		return nil, driverdomain.ErrDriverNotFound
	}
	copied := *r.driver
	return &copied, nil
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

// fakeEventPublisher is a thread-safe event sink. The create usecase publishes
// the order_created event from a delayed (500ms) background goroutine while the
// main flow publishes the searching event synchronously — both write the same
// sink, so it must synchronize (a plain slice append would be a data race
// under -race).
type fakeEventPublisher struct {
	mu     sync.Mutex
	events []orderdomain.Event
}

func (p *fakeEventPublisher) Publish(_ context.Context, event orderdomain.Event) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.events = append(p.events, event)
	return nil
}

// Events returns a snapshot of all published events.
func (p *fakeEventPublisher) Events() []orderdomain.Event {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]orderdomain.Event, len(p.events))
	copy(out, p.events)
	return out
}
