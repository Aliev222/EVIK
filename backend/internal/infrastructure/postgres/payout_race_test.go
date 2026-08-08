//go:build integration

package postgres_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
	"evik/backend/internal/infrastructure/postgres"
)

func TestPayout_ConcurrentCreateExceedsBalance(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "payout-race-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	_, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 50000, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID)
	if err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)

	start := make(chan struct{})
	var wg sync.WaitGroup
	var mu sync.Mutex
	successCount := 0
	insufficientCount := 0

	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			<-start
			now := time.Now()
			payout := &paymentdomain.Payout{
				ID:        "payout-race-" + uuid(),
				DriverID:  driverID,
				Provider:  paymentdomain.ProviderYooKassa,
				Amount:    40000,
				Currency:  "RUB",
				Status:    paymentdomain.PayoutStatusCreated,
				CreatedAt: now,
				UpdatedAt: now,
			}
			_, err := payRepo.CreatePayout(context.Background(), payout, "pk-race-"+uuid())
			mu.Lock()
			defer mu.Unlock()
			switch {
			case err == nil:
				successCount++
			case errors.Is(err, paymentdomain.ErrInsufficientFunds):
				insufficientCount++
			default:
				t.Errorf("goroutine %d: unexpected error: %v", idx, err)
			}
		}(i)
	}
	close(start)
	wg.Wait()

	if successCount != 1 {
		t.Fatalf("expected exactly 1 successful payout, got %d", successCount)
	}
	if insufficientCount != 1 {
		t.Fatalf("expected exactly 1 ErrInsufficientFunds, got %d", insufficientCount)
	}

	var balance int64
	if err := db.QueryRow(`SELECT available_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&balance); err != nil {
		t.Fatalf("query balance: %v", err)
	}
	if balance < 0 {
		t.Fatalf("available_balance went negative: %d", balance)
	}
}

func TestApprovePayout_RejectsWhenBalanceInsufficient(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "payout-approve-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	_, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 50000, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID)
	if err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)

	now := time.Now()
	payoutID := "payout-approve-" + uuid()
	created, err := payRepo.CreatePayout(context.Background(), &paymentdomain.Payout{
		ID:        payoutID,
		DriverID:  driverID,
		Provider:  paymentdomain.ProviderYooKassa,
		Amount:    40000,
		Currency:  "RUB",
		Status:    paymentdomain.PayoutStatusCreated,
		CreatedAt: now,
		UpdatedAt: now,
	}, "pk-approve-"+uuid())
	if err != nil {
		t.Fatalf("CreatePayout: %v", err)
	}
	if created == nil || created.Amount != 40000 {
		t.Fatalf("payout not created correctly: %+v", created)
	}

	// Simulate the balance being spent elsewhere between request and approval
	// (e.g. funds consumed by something other than this payout).
	if _, err := db.Exec(`UPDATE driver_wallets SET available_balance = 10000, updated_at = NOW() WHERE driver_id = $1`, driverID); err != nil {
		t.Fatalf("reduce balance: %v", err)
	}

	_, err = payRepo.ApprovePayout(context.Background(), payoutID, "moderator-1", "", now)
	if err != paymentdomain.ErrInsufficientFunds {
		t.Fatalf("expected ErrInsufficientFunds, got %v", err)
	}

	var balance int64
	if err := db.QueryRow(`SELECT available_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&balance); err != nil {
		t.Fatalf("query balance: %v", err)
	}
	if balance != 10000 {
		t.Fatalf("balance changed on failed approve: expected 10000, got %d", balance)
	}
	if balance < 0 {
		t.Fatalf("available_balance went negative: %d", balance)
	}

	st, err := payRepo.GetPayout(context.Background(), payoutID)
	if err != nil {
		t.Fatalf("GetPayout: %v", err)
	}
	if st.Status != paymentdomain.PayoutStatusCreated {
		t.Fatalf("expected payout still 'created', got %s", st.Status)
	}
}
