//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"evik/backend/internal/domain/settings"
	"evik/backend/internal/infrastructure/postgres"
	driveruc "evik/backend/internal/usecase/driver"
)

type debtGateClock struct{}

func (debtGateClock) Now() time.Time { return time.Date(2026, 8, 15, 12, 0, 0, 0, time.UTC) }

// End-to-end check of the debt gate against a real database: the repository's
// DriverDebtBalance feeds EnsureCanWork, the seeded platform setting controls
// the threshold, and reducing the debt unblocks the driver. Payouts remain
// available regardless of the outstanding debt.
func TestDebtGateBlocksWorkAboveThreshold_Integration(t *testing.T) {
	ctx := context.Background()
	db, cleanup := setupTestDB(t)
	defer cleanup()

	truncateAll(t, db)

	const driverID = "driver-debt-1"
	seedUser(t, db, driverID, "driver")

	if err := execDB(t, db, `INSERT INTO drivers (id, user_id, status, last_seen_at, updated_at) VALUES ($1,$2,'offline',NOW(),NOW())`, driverID, driverID); err != nil {
		t.Fatalf("insert driver: %v", err)
	}
	// Approved documents + verified tax so the ONLY failing gate is the debt.
	if err := execDB(t, db, `
		INSERT INTO driver_verifications (id, user_id, full_name, phone, city, vehicle_model, vehicle_plate, vehicle_type, status, submitted_at, updated_at)
		VALUES ($1,$1,'Driver','+79990000000','city','Ford','А111АА77','light','approved',NOW(),NOW())`, driverID); err != nil {
		t.Fatalf("insert verification: %v", err)
	}
	if err := execDB(t, db, `
		INSERT INTO driver_tax_profiles (driver_id, inn, taxpayer_type, verification_status, created_at, updated_at)
		VALUES ($1,'1234567890','self_employed','verified',NOW(),NOW())`, driverID); err != nil {
		t.Fatalf("insert tax profile: %v", err)
	}
	// 150000 kopecks = 1500 ₽ debt, above the 1000 ₽ threshold.
	if err := execDB(t, db, `
		INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1,$2,0,0,150000,'RUB',NOW(),NOW())`, "wallet-"+driverID, driverID); err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	settingsRepo := postgres.NewSettingsRepository(db)
	if err := settingsRepo.Upsert(ctx, settings.MaxCashDebtKopecksKey, 100000); err != nil {
		t.Fatalf("upsert max_cash_debt_kopecks: %v", err)
	}

	userRepo := postgres.NewUserRepository(db)
	gates := driveruc.NewGateService(userRepo, settingsRepo, debtGateClock{}, false, false, false)

	blocked := errors.Is(gates.EnsureCanWork(ctx, driverID), driveruc.ErrOutstandingDebtBlocksWork)
	if !blocked {
		t.Fatal("expected debt above threshold to block work")
	}

	// Payout of already-earned money must NOT be blocked by the debt.
	if err := gates.EnsureCanRequestPayout(ctx, driverID); err != nil {
		t.Fatalf("expected payout gate to pass despite debt, got %v", err)
	}

	// Repay debt below the threshold → unblocked.
	if err := execDB(t, db, `UPDATE driver_wallets SET debt_balance = 80000, updated_at = NOW() WHERE driver_id = $1`, driverID); err != nil {
		t.Fatalf("lower debt: %v", err)
	}
	if err := gates.EnsureCanWork(ctx, driverID); err != nil {
		t.Fatalf("expected work gate to pass after debt reduction, got %v", err)
	}

	// Full repayment → unblocked.
	if err := execDB(t, db, `UPDATE driver_wallets SET debt_balance = 0, updated_at = NOW() WHERE driver_id = $1`, driverID); err != nil {
		t.Fatalf("clear debt: %v", err)
	}
	if err := gates.EnsureCanWork(ctx, driverID); err != nil {
		t.Fatalf("expected work gate to pass after full repayment, got %v", err)
	}
}

// DriverDebtBalance must return 0 for a driver without a wallet row.
func TestDriverDebtBalanceNoWalletIsZero_Integration(t *testing.T) {
	ctx := context.Background()
	db, cleanup := setupTestDB(t)
	defer cleanup()
	truncateAll(t, db)

	const driverID = "driver-debt-nw"
	seedUser(t, db, driverID, "driver")
	if err := execDB(t, db, `INSERT INTO drivers (id, user_id, status, last_seen_at, updated_at) VALUES ($1,$2,'offline',NOW(),NOW())`, driverID, driverID); err != nil {
		t.Fatalf("insert driver: %v", err)
	}

	userRepo := postgres.NewUserRepository(db)
	debt, err := userRepo.DriverDebtBalance(ctx, driverID)
	if err != nil {
		t.Fatalf("DriverDebtBalance: %v", err)
	}
	if debt != 0 {
		t.Fatalf("debt = %d, want 0 for driver without wallet", debt)
	}
}

func execDB(t *testing.T, db *sql.DB, query string, args ...any) error {
	t.Helper()
	_, err := db.ExecContext(context.Background(), query, args...)
	return err
}