//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
	"evik/backend/internal/infrastructure/postgres"

	"github.com/jackc/pgx/v5/pgconn"
)

// Adversarial/edge integration coverage for the payout / wallet money logic on
// top of payout_race_test.go, race_test.go and split_test.go.

func seedWallet(t *testing.T, db *sql.DB, driverID string, available, pending, debt int64) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID, available, pending, debt)
	if err != nil {
		t.Fatalf("insert wallet: %v", err)
	}
}

// TestPayout_ConcurrentCreateExceedsBalance_ThreePlus extends the two-goroutine
// race from TestPayout_ConcurrentCreateExceedsBalance to a 6-way race where the
// combined demand (6 × 30000 = 180000) vastly exceeds the 50000 balance:
// exactly one payout may pass and the balance must never go negative.
func TestPayout_ConcurrentCreateExceedsBalance_ThreePlus(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "payout-many-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedWallet(t, db, driverID, 50000, 0, 0)

	payRepo := postgres.NewPaymentRepository(db)

	const (
		goroutines = 6
		amount     = 30000
	)
	start := make(chan struct{})
	var wg sync.WaitGroup
	var mu sync.Mutex
	successCount, insufficientCount := 0, 0

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			<-start
			now := time.Now()
			payout := &paymentdomain.Payout{
				ID:        fmt.Sprintf("payout-many-%d-%s", idx, uuid()),
				DriverID:  driverID,
				Provider:  paymentdomain.ProviderYooKassa,
				Amount:    amount,
				Currency:  "RUB",
				Status:    paymentdomain.PayoutStatusCreated,
				CreatedAt: now,
				UpdatedAt: now,
			}
			_, err := payRepo.CreatePayout(context.Background(), payout, "pk-many-"+uuid())
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
	if insufficientCount != goroutines-1 {
		t.Fatalf("expected %d ErrInsufficientFunds, got %d", goroutines-1, insufficientCount)
	}

	var balance int64
	if err := db.QueryRow(`SELECT available_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&balance); err != nil {
		t.Fatalf("query balance: %v", err)
	}
	if balance < 0 {
		t.Fatalf("available_balance went negative: %d", balance)
	}
}

// TestApprovePayout_RejectsFailedPayout verifies a payout that was marked
// failed by a provider error can never be approved afterwards, and the failed
// flag is not silently overwritten.
func TestApprovePayout_RejectsFailedPayout(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "payout-failed-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedWallet(t, db, driverID, 100000, 0, 0)

	payRepo := postgres.NewPaymentRepository(db)
	now := time.Now()

	payoutID := "payout-failed-" + uuid()
	if _, err := payRepo.CreatePayout(context.Background(), &paymentdomain.Payout{
		ID: payoutID, DriverID: driverID, Provider: paymentdomain.ProviderYooKassa,
		Amount: 40000, Currency: "RUB", Status: paymentdomain.PayoutStatusCreated,
		CreatedAt: now, UpdatedAt: now,
	}, "pk-failed-"+uuid()); err != nil {
		t.Fatalf("CreatePayout: %v", err)
	}
	if err := payRepo.MarkPayoutFailed(context.Background(), payoutID, "yookassa 503"); err != nil {
		t.Fatalf("MarkPayoutFailed: %v", err)
	}

	_, err := payRepo.ApprovePayout(context.Background(), payoutID, "moderator-1", "", now)
	if !errors.Is(err, paymentdomain.ErrPayoutNotApprovable) {
		t.Fatalf("ApprovePayout on failed payout: err = %v, want ErrPayoutNotApprovable", err)
	}

	var balance int64
	if err := db.QueryRow(`SELECT available_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&balance); err != nil {
		t.Fatalf("query balance: %v", err)
	}
	if balance != 100000 {
		t.Fatalf("balance = %d, want 100000 (failed payout must not be debited)", balance)
	}

	st, err := payRepo.GetPayout(context.Background(), payoutID)
	if err != nil {
		t.Fatalf("GetPayout: %v", err)
	}
	if st.Status != paymentdomain.PayoutStatusFailed {
		t.Fatalf("payout status = %q, want %q (failed must not flip to paid)", st.Status, paymentdomain.PayoutStatusFailed)
	}
}

// TestWalletNonNegativeCheckConstraints verifies the DB-level CHECK constraints
// from migration 20260808 fire on any attempt to drive available/pending/debt
// balance below zero.
func TestWalletNonNegativeCheckConstraints(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "wallet-check-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedWallet(t, db, driverID, 1000, 1000, 1000)

	cases := []struct {
		column string
		name   string
	}{
		{"available_balance", "driver_wallets_available_nonneg"},
		{"pending_balance", "driver_wallets_pending_nonneg"},
		{"debt_balance", "driver_wallets_debt_nonneg"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := db.Exec(`UPDATE driver_wallets SET `+tc.column+` = -1 WHERE driver_id = $1`, driverID)
			if err == nil {
				t.Fatalf("expected CHECK violation for %s = -1, got nil", tc.column)
			}
			var pgErr *pgconn.PgError
			if !errors.As(err, &pgErr) || pgErr.ConstraintName != tc.name {
				t.Fatalf("expected constraint %q, got: %v", tc.name, err)
			}
		})
	}

	// The non-negative invariant must survive all three failures.
	var avail, pending, debt int64
	if err := db.QueryRow(`SELECT available_balance, pending_balance, debt_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&avail, &pending, &debt); err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if avail != 1000 || pending != 1000 || debt != 1000 {
		t.Fatalf("wallet changed after constraint violations: avail=%d pending=%d debt=%d", avail, pending, debt)
	}
}

// TestPayout_SameIdempotencyKey_NoDuplicate verifies the idempotency key on
// payouts: a second CreatePayout with the same key returns the same payout and
// does not create a second reservation row.
func TestPayout_SameIdempotencyKey_NoDuplicate(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "payout-ik-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedWallet(t, db, driverID, 50000, 0, 0)

	payRepo := postgres.NewPaymentRepository(db)
	now := time.Now()
	key := "pk-dedupe-" + uuid()

	newPayout := func() *paymentdomain.Payout {
		return &paymentdomain.Payout{
			ID: "payout-ik-" + uuid(), DriverID: driverID, Provider: paymentdomain.ProviderYooKassa,
			Amount: 30000, Currency: "RUB", Status: paymentdomain.PayoutStatusCreated,
			CreatedAt: now, UpdatedAt: now,
		}
	}

	first, err := payRepo.CreatePayout(context.Background(), newPayout(), key)
	if err != nil {
		t.Fatalf("first CreatePayout: %v", err)
	}
	second, err := payRepo.CreatePayout(context.Background(), newPayout(), key)
	if err != nil {
		t.Fatalf("second CreatePayout: %v", err)
	}

	if first.ID != second.ID {
		t.Fatalf("same idempotency key returned different payouts: %s vs %s", first.ID, second.ID)
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM payouts WHERE driver_id = $1`, driverID).Scan(&count); err != nil {
		t.Fatalf("count payouts: %v", err)
	}
	if count != 1 {
		t.Fatalf("payout rows = %d, want 1 (duplicate key must not create a second payout)", count)
	}

	// The duplicate must not consume any additional reserved funds: the wallet
	// still allows one more 30000 payout (50000 - 30000 = 20000 < 30000 no; but
	// a 15000 payout is fine) proving no double reservation.
	third, err := payRepo.CreatePayout(context.Background(), &paymentdomain.Payout{
		ID: "payout-ik-third-" + uuid(), DriverID: driverID, Provider: paymentdomain.ProviderYooKassa,
		Amount: 15000, Currency: "RUB", Status: paymentdomain.PayoutStatusCreated,
		CreatedAt: now, UpdatedAt: now,
	}, "pk-third-"+uuid())
	if err != nil {
		t.Fatalf("payout after duplicate reservation: %v", err)
	}
	if third.Amount != 15000 {
		t.Fatalf("third payout amount = %d, want 15000", third.Amount)
	}
}

// TestWallet_AvailablePendingDebtNotMixed verifies the three balance buckets are
// strictly isolated: a payout can only spend available_balance (never pending
// or debt), and approving it moves only the available bucket.
func TestWallet_AvailablePendingDebtNotMixed(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "wallet-buckets-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedWallet(t, db, driverID, 100000, 50000, 10000)

	payRepo := postgres.NewPaymentRepository(db)
	now := time.Now()

	// 120000 exceeds available (100000) but not available+pending (150000).
	// Payout must refuse to touch pending money.
	_, err := payRepo.CreatePayout(context.Background(), &paymentdomain.Payout{
		ID: "payout-buckets-1-" + uuid(), DriverID: driverID, Provider: paymentdomain.ProviderYooKassa,
		Amount: 120000, Currency: "RUB", Status: paymentdomain.PayoutStatusCreated,
		CreatedAt: now, UpdatedAt: now,
	}, "pk-buckets-1-"+uuid())
	if !errors.Is(err, paymentdomain.ErrInsufficientFunds) {
		t.Fatalf("payout from pending funds: err = %v, want ErrInsufficientFunds", err)
	}

	// 90000 fits in available → must succeed, and approval must debit only the
	// available bucket.
	payout, err := payRepo.CreatePayout(context.Background(), &paymentdomain.Payout{
		ID: "payout-buckets-2-" + uuid(), DriverID: driverID, Provider: paymentdomain.ProviderYooKassa,
		Amount: 90000, Currency: "RUB", Status: paymentdomain.PayoutStatusCreated,
		CreatedAt: now, UpdatedAt: now,
	}, "pk-buckets-2-"+uuid())
	if err != nil {
		t.Fatalf("CreatePayout 90000: %v", err)
	}
	if _, err := payRepo.ApprovePayout(context.Background(), payout.ID, "moderator-1", "", now); err != nil {
		t.Fatalf("ApprovePayout: %v", err)
	}

	var avail, pending, debt int64
	if err := db.QueryRow(`SELECT available_balance, pending_balance, debt_balance FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&avail, &pending, &debt); err != nil {
		t.Fatalf("query wallet: %v", err)
	}
	if avail != 10000 {
		t.Errorf("available_balance = %d, want 10000 (100000 - 90000)", avail)
	}
	if pending != 50000 {
		t.Errorf("pending_balance = %d, want 50000 (payout must not touch pending)", pending)
	}
	if debt != 10000 {
		t.Errorf("debt_balance = %d, want 10000 (payout must not touch debt)", debt)
	}
}

// seedCashOrderForSplit inserts an order ready for financial completion via the
// cash path (no payment row) and returns (userID, driverID, orderID).
func seedCashOrderForSplit(t *testing.T, db *sql.DB, total int64) (string, string, string) {
	t.Helper()
	userID := "user-split-" + uuid()
	driverID := "driver-split-" + uuid()
	seedUser(t, db, userID, "client")
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	orderID := "order-split-" + uuid()
	_, err := db.Exec(`
		INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			tow_truck_type, status, price_total, payment_method, financial_status, created_at, updated_at)
		VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', 'awaiting_payment', $4, 'cash', 'pending', NOW(), NOW())`,
		orderID, userID, driverID, total)
	if err != nil {
		t.Fatalf("insert split order: %v", err)
	}
	return userID, driverID, orderID
}

// TestSplitInvariant_AcrossPercentages verifies price_total = driver_amount +
// commission_amount holds for several commission rates (15 default, 20, 33 and
// 0 subscription), including half-up rounding at the kopecks level.
func TestSplitInvariant_AcrossPercentages(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	cases := []struct {
		pct     int
		total   int64
	}{
		{pct: 15, total: 100000},
		{pct: 15, total: 1001},
		{pct: 20, total: 100000},
		{pct: 33, total: 100000},
		{pct: 0, total: 100000},
	}

	for _, tc := range cases {
		name := fmt.Sprintf("pct-%d-total-%d", tc.pct, tc.total)
		t.Run(name, func(t *testing.T) {
			_, driverID, orderID := seedCashOrderForSplit(t, db, tc.total)

			if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-split-"+uuid(), 600, tc.pct); err != nil {
				t.Fatalf("CompleteOrderFinancially: %v", err)
			}

			var priceTotal, driverAmount, commissionAmount int64
			var finStatus string
			if err := db.QueryRow(`SELECT price_total, driver_amount, commission_amount, financial_status FROM orders WHERE id = $1`, orderID).
				Scan(&priceTotal, &driverAmount, &commissionAmount, &finStatus); err != nil {
				t.Fatalf("query split order: %v", err)
			}
			if finStatus != "completed" {
				t.Fatalf("financial_status = %q, want completed", finStatus)
			}
			if driverAmount+commissionAmount != priceTotal {
				t.Fatalf("split invariant broken: driver(%d) + commission(%d) = %d != total(%d)",
					driverAmount, commissionAmount, driverAmount+commissionAmount, priceTotal)
			}
			if driverAmount < 0 || commissionAmount < 0 {
				t.Fatalf("negative split: driver=%d commission=%d", driverAmount, commissionAmount)
			}

			// Cash path records the commission as debt.
			wallet, err := payRepo.GetDriverWallet(ctx, driverID)
			if err != nil {
				t.Fatalf("GetDriverWallet: %v", err)
			}
			if wallet.DebtBalance != commissionAmount {
				t.Errorf("debt_balance = %d, want commission %d", wallet.DebtBalance, commissionAmount)
			}
		})
	}
}