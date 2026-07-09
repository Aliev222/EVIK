//go:build integration

package postgres_test

import (
	"context"
	"sync"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	"evik/backend/internal/infrastructure/postgres"
)

var _ = paymentdomain.ErrInsufficientFunds

func TestAcceptOrder_Race(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	userID := "race-client"
	driver1 := "race-driver-1"
	driver2 := "race-driver-2"

	seedUser(t, db, userID, "client")
	seedUser(t, db, driver1, "driver")
	seedUser(t, db, driver2, "driver")
	seedDriver(t, db, driver1)
	seedDriver(t, db, driver2)

	orderID := "race-order-" + uuid()

	_, err := db.Exec(`
INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, created_at, updated_at)
VALUES ($1, $2, 42.0, 47.5, 42.1, 47.6, 'winch', 'searching', cents_to_rub(500000), NOW(), NOW())`,
		orderID, userID)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	orderRepo := postgres.NewOrderRepository(db)

	for iter := 0; iter < 50; iter++ {
		start := make(chan struct{})
		var wg sync.WaitGroup
		var mu sync.Mutex
		successCount := 0

		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			_, err := orderRepo.AcceptOrder(context.Background(), orderID, driver1)
			if err == nil {
				mu.Lock()
				successCount++
				mu.Unlock()
			}
		}()
		go func() {
			defer wg.Done()
			<-start
			_, err := orderRepo.AcceptOrder(context.Background(), orderID, driver2)
			if err == nil {
				mu.Lock()
				successCount++
				mu.Unlock()
			}
		}()

		close(start)
		wg.Wait()

		if successCount != 1 {
			t.Fatalf("iteration %d: expected exactly 1 success, got %d", iter, successCount)
		}

		ord, err := orderRepo.GetByID(context.Background(), orderID)
		if err != nil {
			t.Fatalf("iteration %d: GetByID: %v", iter, err)
		}
		if ord.DriverID == nil || *ord.DriverID == "" {
			t.Fatalf("iteration %d: driver_id is nil after accept", iter)
		}
		if ord.Status != orderdomain.StatusAccepted {
			t.Fatalf("iteration %d: driver=%s expected status 'accepted', got %s", iter, *ord.DriverID, ord.Status)
		}

		_, err = db.Exec(`UPDATE orders SET driver_id = NULL, status = 'searching', updated_at = NOW() WHERE id = $1`, orderID)
		if err != nil {
			t.Fatalf("iteration %d: reset order: %v", iter, err)
		}
	}
}

func TestWallet_ParallelCredit(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "wallet-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	_, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID)
	if err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	var wg sync.WaitGroup
	concurrent := 10
	amountPerOp := int64(100000)

	for i := 0; i < concurrent; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			ctx := context.Background()
			tx, err := db.BeginTx(ctx, nil)
			if err != nil {
				t.Errorf("begin tx %d: %v", idx, err)
				return
			}
			defer tx.Rollback()

			if _, err := tx.ExecContext(ctx, `SELECT id FROM driver_wallets WHERE driver_id = $1 FOR UPDATE`, driverID); err != nil {
				t.Errorf("lock wallet %d: %v", idx, err)
				return
			}

			if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET available_balance = available_balance + cents_to_rub($1), updated_at = NOW() WHERE driver_id = $2`, amountPerOp, driverID); err != nil {
				t.Errorf("update wallet %d: %v", idx, err)
				return
			}

			if err := tx.Commit(); err != nil {
				t.Errorf("commit %d: %v", idx, err)
			}
		}(i)
	}
	wg.Wait()

	var balance int64
	if err := db.QueryRow(`SELECT rub_to_cents(available_balance) FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&balance); err != nil {
		t.Fatalf("query balance: %v", err)
	}

	expected := int64(concurrent) * amountPerOp
	if balance != expected {
		t.Fatalf("balance: expected %d, got %d", expected, balance)
	}
}

func TestWallet_ParallelIdempotentKey(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "wallet-idemp-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	_, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID)
	if err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	orderID := "idemp-order-" + uuid()
	userID := "idemp-client-" + uuid()
	seedUser(t, db, userID, "client")

	_, err = db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, created_at, updated_at)
VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', cents_to_rub(500000), NOW(), NOW())`,
		orderID, userID, driverID)
	if err != nil {
		t.Fatalf("insert order: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)

	var wg sync.WaitGroup
	start := make(chan struct{})
	errs := make(chan error, 5)

	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			<-start
			ik := "identical-ik-test"
			err := payRepo.CompleteOrderFinancially(context.Background(), orderID, ik, 0, 15)
			if err != nil {
				errs <- err
			}
		}(i)
	}

	close(start)
	wg.Wait()
	close(errs)

	for err := range errs {
		t.Logf("error (expected idempotent): %v", err)
	}

	txs, err := payRepo.ListWalletTransactions(context.Background(), driverID, 100)
	if err != nil {
		t.Fatalf("ListWalletTransactions: %v", err)
	}

	commissions := 0
	for _, tx := range txs {
		if tx.IdempotencyKey == "identical-ik-test:cash_debt" || tx.IdempotencyKey == "identical-ik-test" {
			commissions++
		}
	}
	if commissions > 1 {
		t.Fatalf("idempotent key applied %d times, expected 1", commissions)
	}
}

func TestWallet_InsufficientFunds(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "wallet-insuff-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	_, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID)
	if err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)

	payout, err := payRepo.CreatePayout(context.Background(), &paymentdomain.Payout{
		ID:       "payout-" + uuid(),
		DriverID: driverID,
		Provider: paymentdomain.ProviderYooKassa,
		Amount: 50000,
		Currency: "RUB",
		Status: paymentdomain.PayoutStatusCreated,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}, "pk-" + uuid())
	if err == nil {
		t.Fatalf("expected ErrInsufficientFunds, got payout %+v", payout)
	}
	if err != paymentdomain.ErrInsufficientFunds {
		t.Fatalf("expected ErrInsufficientFunds, got %v", err)
	}

	var negative int64
	if err := db.QueryRow(`SELECT rub_to_cents(available_balance) FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&negative); err != nil {
		t.Fatalf("query balance: %v", err)
	}
	if negative < 0 {
		t.Fatalf("balance went negative: %d", negative)
	}
}