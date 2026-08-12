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

func newCancelUC(db *sql.DB) (*orderuc.CancelOrderUseCase, *postgres.OrderRepository, *postgres.DriverRepository) {
	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)
	uc := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, integrationPublisher{}, integrationClock{now: now}, integrationLogger{})
	return uc, orderRepo, driverRepo
}

// TestCancelOrderUseCase_AfterAccept_DriverFreed is the end-to-end guard for
// the «отмена освобождает водителя» contract: accept via the real
// AcceptOrderUseCase, then cancel via the real CancelOrderUseCase — the order
// must land in cancelled with cancelled_at + cancel_reason persisted and the
// driver must be back online with no current order.
func TestCancelOrderUseCase_AfterAccept_DriverFreed(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)

	clientID := "client-cx"
	driverID := "driver-cx"
	orderID := "order-cx"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID, clientID)
	setOrderSearching(t, db, orderID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	acceptUC := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})
	if _, err := acceptUC.Execute(ctx, orderID, driverID); err != nil {
		t.Fatalf("accept: %v", err)
	}

	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, integrationPublisher{}, integrationClock{now: now}, integrationLogger{})
	ord, err := cancelUC.Execute(ctx, orderID, "client_cancelled")
	if err != nil {
		t.Fatalf("cancel: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
	if ord.CancelledAt == nil {
		t.Fatal("CancelledAt is nil after cancellation")
	}
	if ord.CancelReason != "client_cancelled" {
		t.Fatalf("CancelReason = %q, want client_cancelled", ord.CancelReason)
	}

	var status string
	var currentOrderID *string
	if err := db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&status, &currentOrderID); err != nil {
		t.Fatalf("query driver: %v", err)
	}
	if status != string(driverdomain.StatusOnline) {
		t.Fatalf("driver status = %q, want online after cancellation", status)
	}
	if currentOrderID != nil {
		t.Fatalf("driver current_order_id = %v, want nil", *currentOrderID)
	}
}

// TestCancelOrderUseCase_AtCreatedStage verifies cancellation of an order
// that never left the created state: no driver involved, clean transition to
// cancelled with the reason persisted in the database.
func TestCancelOrderUseCase_AtCreatedStage(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()

	clientID := "client-cx2"
	orderID := "order-cx2"
	seedUser(t, db, clientID, "client")
	seedOrderRaw(t, db, orderID, clientID)

	cancelUC, orderRepo, _ := newCancelUC(db)
	ord, err := cancelUC.Execute(ctx, orderID, "отмена из-за мороза")
	if err != nil {
		t.Fatalf("cancel: %v", err)
	}
	if ord.Status != orderdomain.StatusCancelled {
		t.Fatalf("status = %q, want cancelled", ord.Status)
	}
	if ord.CancelReason != "order_cancelled" {
		t.Fatalf("CancelReason = %q, want order_cancelled (unknown reason normalized)", ord.CancelReason)
	}

	stored, err := orderRepo.GetByID(ctx, orderID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if stored.Status != orderdomain.StatusCancelled || stored.CancelledAt == nil {
		t.Fatalf("persisted = %q (cancelled_at=%v), want cancelled + timestamp", stored.Status, stored.CancelledAt)
	}
	if stored.CancelReason != "order_cancelled" {
		t.Fatalf("persisted CancelReason = %q, want order_cancelled", stored.CancelReason)
	}
}

// TestCancelThenAccept_CancelWins is the deterministic counterpart of the
// concurrent race: when the cancellation is already committed, a later accept
// must fail with ErrOrderAlreadyTaken and must not resurrect the order or
// disturb the driver.
func TestCancelThenAccept_CancelWins(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)

	clientID := "client-cx3"
	driverID := "driver-cx3"
	orderID := "order-cx3"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID, clientID)
	setOrderSearching(t, db, orderID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, integrationPublisher{}, integrationClock{now: now}, integrationLogger{})
	acceptUC := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})

	if _, err := cancelUC.Execute(ctx, orderID, "client_cancelled"); err != nil {
		t.Fatalf("cancel: %v", err)
	}
	if _, err := acceptUC.Execute(ctx, orderID, driverID); !errors.Is(err, orderdomain.ErrOrderAlreadyTaken) {
		t.Fatalf("accept after cancel: err = %v, want ErrOrderAlreadyTaken", err)
	}

	var orderStatus string
	if err := db.QueryRow(`SELECT status FROM orders WHERE id = $1`, orderID).Scan(&orderStatus); err != nil {
		t.Fatalf("query order: %v", err)
	}
	if orderStatus != string(orderdomain.StatusCancelled) {
		t.Fatalf("order status = %q after failed accept, want cancelled", orderStatus)
	}

	var driverStatus string
	var currentOrderID *string
	if err := db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&driverStatus, &currentOrderID); err != nil {
		t.Fatalf("query driver: %v", err)
	}
	if driverStatus != string(driverdomain.StatusOnline) || currentOrderID != nil {
		t.Fatalf("driver after failed accept = %q / %v, want online / nil", driverStatus, currentOrderID)
	}
}

// raceOutcome summarizes one run of the cancel-vs-accept race.
type raceOutcome struct {
	iterations  int
	acceptWins  int
	cancelFirst int
	orderLive   int // iterations where the order ended up NOT cancelled
	driverStuck int // iterations where the driver stayed busy on the order
	acceptErrs  int
	cancelErrs  int
}

// runCancelAcceptRace executes the accept/cancel race against the real
// postgres repositories. Even iterations give the accept goroutine a small
// head start (exercising the accept-commits-then-cancel-overwrites
// interleave), odd iterations give the cancel the head start (exercising the
// accept-claim-misses ordering). Both goroutines run to completion and the
// post-race database state is classified into the outcome counters.
func runCancelAcceptRace(t *testing.T, db *sql.DB, iterations int) raceOutcome {
	t.Helper()
	ctx := context.Background()
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)

	clientID := "client-race"
	driverID := "driver-race"
	orderID := "order-race"
	seedUser(t, db, clientID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedOrderRaw(t, db, orderID, clientID)

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db, nil)
	acceptUC := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, nil, nil, nil, nil, integrationPublisher{}, nil, integrationClock{now: now}, integrationLogger{})
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, integrationPublisher{}, integrationClock{now: now}, integrationLogger{})

	var out raceOutcome
	for iter := 0; iter < iterations; iter++ {
		out.iterations++
		if _, err := db.Exec(`UPDATE orders SET status = 'searching', driver_id = NULL, updated_at = NOW() WHERE id = $1`, orderID); err != nil {
			t.Fatalf("reset order: %v", err)
		}
		if _, err := db.Exec(`UPDATE drivers SET status = 'online', current_order_id = NULL, updated_at = NOW() WHERE id = $1`, driverID); err != nil {
			t.Fatalf("reset driver: %v", err)
		}

		start := make(chan struct{})
		var wg sync.WaitGroup
		var mu sync.Mutex
		var accepted bool

		run := func(fn func()) {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				fn()
			}()
		}

		if iter%2 == 0 {
			run(func() {
				if _, err := acceptUC.Execute(ctx, orderID, driverID); err == nil {
					mu.Lock()
					accepted = true
					mu.Unlock()
				} else if !errors.Is(err, orderdomain.ErrOrderAlreadyTaken) {
					mu.Lock()
					out.acceptErrs++
					mu.Unlock()
				}
			})
			run(func() {
				time.Sleep(2 * time.Millisecond)
				if _, err := cancelUC.Execute(ctx, orderID, "client_cancelled"); err != nil {
					mu.Lock()
					out.cancelErrs++
					mu.Unlock()
				}
			})
		} else {
			out.cancelFirst++
			run(func() {
				if _, err := cancelUC.Execute(ctx, orderID, "client_cancelled"); err != nil {
					mu.Lock()
					out.cancelErrs++
					mu.Unlock()
				}
			})
			run(func() {
				time.Sleep(2 * time.Millisecond)
				if _, err := acceptUC.Execute(ctx, orderID, driverID); err == nil {
					mu.Lock()
					accepted = true
					mu.Unlock()
				} else if !errors.Is(err, orderdomain.ErrOrderAlreadyTaken) {
					mu.Lock()
					out.acceptErrs++
					mu.Unlock()
				}
			})
		}
		close(start)
		wg.Wait()

		var orderStatus string
		if err := db.QueryRow(`SELECT status FROM orders WHERE id = $1`, orderID).Scan(&orderStatus); err != nil {
			t.Fatalf("iter %d: query order status: %v", iter, err)
		}
		if orderStatus != string(orderdomain.StatusCancelled) {
			out.orderLive++
		}

		var driverStatus string
		var currentOrderID *string
		if err := db.QueryRow(`SELECT status, current_order_id FROM drivers WHERE id = $1`, driverID).Scan(&driverStatus, &currentOrderID); err != nil {
			t.Fatalf("iter %d: query driver: %v", iter, err)
		}
		if driverStatus != string(driverdomain.StatusOnline) || currentOrderID != nil {
			out.driverStuck++
		}

		if accepted {
			out.acceptWins++
		}
	}
	return out
}

// TestCancelVsAcceptConcurrent_OrderStatusConsistent is the active half of
// the accept/cancel race contract: no matter the interleaving, the order row
// itself never ends up in a live state («принят и отменён одновременно» is
// impossible at the row level because the accept claim is conditional while
// the cancel update is unconditional — cancel always has the last word).
func TestCancelVsAcceptConcurrent_OrderStatusConsistent(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	out := runCancelAcceptRace(t, db, 60)
	t.Logf("race summary: accept won %d/%d, cancel-first %d, order-live %d, driver-stuck %d, accept errs %d, cancel errs %d",
		out.acceptWins, out.iterations, out.cancelFirst, out.orderLive, out.driverStuck, out.acceptErrs, out.cancelErrs)
	if out.orderLive != 0 {
		t.Fatalf("order ended live (not cancelled) in %d/%d iterations", out.orderLive, out.iterations)
	}
	if out.acceptErrs != 0 || out.cancelErrs != 0 {
		t.Fatalf("unexpected usecase errors: accept %d, cancel %d", out.acceptErrs, out.cancelErrs)
	}
}

// TestCancelVsAcceptConcurrent_DriverNeverStuck is the skipped half of the
// accept/cancel race contract: the driver must never remain bound (busy +
// current_order_id) to an order that was cancelled. This invariant is
// currently VIOLATED in production — see bug id BUG-CANCEL-RACE-DRIVER in
// the report: cancel_order.go decides driver release from the stale
// pre-accept snapshot, so when an accept commits between cancel's read and
// cancel's write, the driver assignment is silently lost and ReleaseOrder is
// never called. Driver remains 'busy' on a cancelled order forever.
func TestCancelVsAcceptConcurrent_DriverNeverStuck(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	out := runCancelAcceptRace(t, db, 60)
	t.Logf("race summary: accept won %d/%d, cancel-first %d, order-live %d, driver-stuck %d, accept errs %d, cancel errs %d",
		out.acceptWins, out.iterations, out.cancelFirst, out.orderLive, out.driverStuck, out.acceptErrs, out.cancelErrs)
	if out.driverStuck != 0 {
		t.Fatalf("driver stayed busy on the cancelled order in %d/%d iterations", out.driverStuck, out.iterations)
	}
	if out.orderLive != 0 {
		t.Fatalf("order ended live (not cancelled) in %d/%d iterations", out.orderLive, out.iterations)
	}
}
