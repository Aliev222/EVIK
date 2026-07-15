//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"sync"
	"testing"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/postgres"
	orderuc "evik/backend/internal/usecase/order"
)

type integrationClock struct{ now time.Time }

func (c integrationClock) Now() time.Time { return c.now }

type integrationPublisher struct{}

func (integrationPublisher) Publish(_ context.Context, _ orderdomain.Event) error { return nil }

type integrationLogger struct{}

func (integrationLogger) Info(string, ...any)         {}
func (integrationLogger) Error(string, error, ...any) {}

func setOrderSearching(t *testing.T, db *sql.DB, orderID string) {
	t.Helper()
	_, err := db.Exec(`UPDATE orders SET status = 'searching', updated_at = NOW() WHERE id = $1`, orderID)
	if err != nil {
		t.Fatalf("set order searching: %v", err)
	}
}

func TestAcceptOrder_Success(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-succ"
	driverID := "driver-succ"
	orderID := "order-succ"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID, clientID)
	setOrderSearching(t, db, orderID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	ord, err := uc.Execute(ctx, orderID, driverID)
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if ord.Status != orderdomain.StatusAccepted {
		t.Fatalf("status = %q, want %q", ord.Status, orderdomain.StatusAccepted)
	}
	if ord.DriverID == nil || *ord.DriverID != driverID {
		t.Fatalf("driver_id = %v, want %s", ord.DriverID, driverID)
	}

	var status string
	var currentOrderID *string
	err = db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&status, &currentOrderID)
	if err != nil {
		t.Fatalf("query driver: %v", err)
	}
	if status != string(driverdomain.StatusBusy) {
		t.Fatalf("driver status = %q, want %q", status, driverdomain.StatusBusy)
	}
	if currentOrderID == nil || *currentOrderID != orderID {
		t.Fatalf("driver current_order_id = %v, want %s", currentOrderID, orderID)
	}
}

func TestAcceptOrder_BusyDriver_Rejected(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-busy"
	driverID := "driver-busy"
	orderID1 := "order-busy-1"
	orderID2 := "order-busy-2"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID1, clientID)
	seedOrderRaw(t, db, orderID2, clientID)
	setOrderSearching(t, db, orderID1)
	setOrderSearching(t, db, orderID2)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	if _, err := uc.Execute(ctx, orderID1, driverID); err != nil {
		t.Fatalf("first accept: %v", err)
	}

	_, err := uc.Execute(ctx, orderID2, driverID)
	if !errors.Is(err, driverdomain.ErrDriverBusy) {
		t.Fatalf("second accept error = %v, want ErrDriverBusy", err)
	}

	var order2Status string
	if err := db.QueryRow(`SELECT status FROM orders WHERE id = $1`, orderID2).Scan(&order2Status); err != nil {
		t.Fatalf("query order2: %v", err)
	}
	if order2Status != string(orderdomain.StatusSearching) {
		t.Fatalf("order2 after reject = %q, want 'searching'", order2Status)
	}

	var status string
	var currentOrderID *string
	db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&status, &currentOrderID)
	if status != string(driverdomain.StatusBusy) {
		t.Fatalf("driver status = %q, want %q", status, driverdomain.StatusBusy)
	}
	if currentOrderID == nil || *currentOrderID != orderID1 {
		t.Fatalf("driver current_order_id = %v, want %s", currentOrderID, orderID1)
	}
}

func TestAcceptOrder_ConcurrentTwoOrders_OneAccepted(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-co"
	driverID := "driver-co"
	orderA := "order-co-a"
	orderB := "order-co-b"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderA, clientID)
	seedOrderRaw(t, db, orderB, clientID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	for iter := 0; iter < 50; iter++ {
		db.Exec(`UPDATE orders SET status = 'searching', driver_id = NULL, updated_at = NOW() WHERE id IN ($1, $2)`, orderA, orderB)
		db.Exec(`UPDATE drivers SET status = 'online', current_order_id = NULL, updated_at = NOW() WHERE id = $1`, driverID)

		start := make(chan struct{})
		var wg sync.WaitGroup
		var mu sync.Mutex
		accepted := 0
		acceptedOrder := ""

		wg.Add(2)
		go func(id string) {
			defer wg.Done()
			<-start
			ord, err := uc.Execute(context.Background(), id, driverID)
			if err == nil {
				mu.Lock()
				accepted++
				acceptedOrder = ord.ID
				mu.Unlock()
			}
		}(orderA)
		go func(id string) {
			defer wg.Done()
			<-start
			ord, err := uc.Execute(context.Background(), id, driverID)
			if err == nil {
				mu.Lock()
				accepted++
				acceptedOrder = ord.ID
				mu.Unlock()
			}
		}(orderB)

		close(start)
		wg.Wait()

		if accepted != 1 {
			t.Fatalf("iter %d: expected 1 accepted, got %d", iter, accepted)
		}

		var driverOrderID *string
		db.QueryRow(`SELECT current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&driverOrderID)
		if driverOrderID == nil || *driverOrderID != acceptedOrder {
			t.Fatalf("iter %d: driver.current_order_id = %v, want %s", iter, driverOrderID, acceptedOrder)
		}

		otherOrder := orderB
		if acceptedOrder == orderB {
			otherOrder = orderA
		}
		var otherStatus string
		db.QueryRow(`SELECT status FROM orders WHERE id = $1`, otherOrder).Scan(&otherStatus)
		if otherStatus != string(orderdomain.StatusSearching) {
			t.Fatalf("iter %d: other order = %q, want 'searching'", iter, otherStatus)
		}
	}
}

func TestAcceptOrder_ConcurrentTwoDrivers_OneWins(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-cd"
	driver1 := "driver-cd-1"
	driver2 := "driver-cd-2"
	orderID := "order-cd"

	seedUser(t, db, clientID, "client")
	seedUser(t, db, driver1, "driver")
	seedUser(t, db, driver2, "driver")
	seedDriver(t, db, driver1)
	seedDriver(t, db, driver2)
	seedOrderRaw(t, db, orderID, clientID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	for iter := 0; iter < 50; iter++ {
		db.Exec(`UPDATE orders SET status = 'searching', driver_id = NULL, updated_at = NOW() WHERE id = $1`, orderID)
		for _, d := range []string{driver1, driver2} {
			db.Exec(`UPDATE drivers SET status = 'online', current_order_id = NULL, updated_at = NOW() WHERE id = $1`, d)
		}

		start := make(chan struct{})
		var wg sync.WaitGroup
		var mu sync.Mutex
		successCount := 0

		wg.Add(2)
		go func(d string) {
			defer wg.Done()
			<-start
			_, err := uc.Execute(context.Background(), orderID, d)
			if err == nil {
				mu.Lock()
				successCount++
				mu.Unlock()
			}
		}(driver1)
		go func(d string) {
			defer wg.Done()
			<-start
			_, err := uc.Execute(context.Background(), orderID, d)
			if err == nil {
				mu.Lock()
				successCount++
				mu.Unlock()
			}
		}(driver2)

		close(start)
		wg.Wait()

		if successCount != 1 {
			t.Fatalf("iter %d: expected 1 success, got %d", iter, successCount)
		}

		var winnerID string
		db.QueryRow(`SELECT driver_id FROM orders WHERE id = $1`, orderID).Scan(&winnerID)
		if winnerID == "" {
			t.Fatalf("iter %d: no winner", iter)
		}

		loser := driver2
		if winnerID == driver2 {
			loser = driver1
		}
		var loserStatus string
		db.QueryRow(`SELECT status FROM drivers WHERE id = $1`, loser).Scan(&loserStatus)
		if loserStatus != string(driverdomain.StatusOnline) {
			t.Fatalf("iter %d: loser = %q, want 'online'", iter, loserStatus)
		}
	}
}

func TestAcceptOrder_ThenComplete_DriverFreed(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-freed"
	driverID := "driver-freed"
	orderID := "order-freed"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID, clientID)
	setOrderSearching(t, db, orderID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	if _, err := uc.Execute(ctx, orderID, driverID); err != nil {
		t.Fatalf("accept: %v", err)
	}

	db.Exec(`UPDATE orders SET status = 'completed', updated_at = NOW(), financially_completed_at = NOW(), financial_status = 'completed' WHERE id = $1`, orderID)
	if err := driverRepo.ReleaseOrder(ctx, driverID, orderID, now); err != nil {
		t.Fatalf("release driver: %v", err)
	}

	var status string
	var currentOrderID *string
	db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&status, &currentOrderID)
	if status != string(driverdomain.StatusOnline) {
		t.Fatalf("status = %q, want %q", status, driverdomain.StatusOnline)
	}
	if currentOrderID != nil {
		t.Fatalf("current_order_id = %v, want nil", currentOrderID)
	}
}

func TestAcceptOrder_ThenCancel_DriverFreed(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-cancel"
	driverID := "driver-cancel"
	orderID := "order-cancel"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID, clientID)
	setOrderSearching(t, db, orderID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	if _, err := uc.Execute(ctx, orderID, driverID); err != nil {
		t.Fatalf("accept: %v", err)
	}

	if err := driverRepo.ReleaseOrder(ctx, driverID, orderID, now); err != nil {
		t.Fatalf("release driver: %v", err)
	}
	db.Exec(`UPDATE orders SET status = 'cancelled', updated_at = NOW() WHERE id = $1`, orderID)

	var status string
	var currentOrderID *string
	db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&status, &currentOrderID)
	if status != string(driverdomain.StatusOnline) {
		t.Fatalf("status = %q, want %q", status, driverdomain.StatusOnline)
	}
	if currentOrderID != nil {
		t.Fatalf("current_order_id = %v, want nil", currentOrderID)
	}
}

func TestAcceptOrder_CanAcceptAgainAfterRelease(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

	clientID := "client-again"
	driverID := "driver-again"
	order1 := "order-again-1"
	order2 := "order-again-2"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, order1, clientID)
	seedOrderRaw(t, db, order2, clientID)
	setOrderSearching(t, db, order1)
	setOrderSearching(t, db, order2)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	uc := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	if _, err := uc.Execute(ctx, order1, driverID); err != nil {
		t.Fatalf("accept first order: %v", err)
	}

	if err := driverRepo.ReleaseOrder(ctx, driverID, order1, now); err != nil {
		t.Fatalf("release driver: %v", err)
	}
	db.Exec(`UPDATE orders SET status = 'completed', updated_at = NOW(), financially_completed_at = NOW(), financial_status = 'completed' WHERE id = $1`, order1)

	var currentOrderID *string
	db.QueryRow(`SELECT current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&currentOrderID)
	if currentOrderID != nil {
		t.Fatalf("driver current_order_id = %v after release, want nil", currentOrderID)
	}

	// Second accept — same driver, new order. This is the critical assertion.
	ord2, err := uc.Execute(ctx, order2, driverID)
	if err != nil {
		t.Fatalf("accept second order after release: %v", err)
	}
	if ord2.Status != orderdomain.StatusAccepted {
		t.Fatalf("second order status = %q, want 'accepted'", ord2.Status)
	}

	var status string
	db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&status, &currentOrderID)
	if status != string(driverdomain.StatusBusy) {
		t.Fatalf("driver status after second accept = %q, want %q", status, driverdomain.StatusBusy)
	}
	if currentOrderID == nil || *currentOrderID != order2 {
		t.Fatalf("driver current_order_id after second accept = %v, want %s", currentOrderID, order2)
	}
}
