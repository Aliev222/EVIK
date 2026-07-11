//go:build integration

package postgres_test

import (
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// TestOrderSplitConstraint verifies the chk_orders_split CHECK constraint added
// in migration 20260605: once financially_completed_at is set, price_total must
// equal commission_amount + driver_amount. While financially_completed_at is
// NULL the split columns are unconstrained (they default to 0).
func TestOrderSplitConstraint(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	userID := "user-" + uuid()
	seedUser(t, db, userID, "client")

	orderID := "order-" + uuid()
	// financially_completed_at IS NULL, amounts default to 0 → insert passes.
	seedOrderRaw(t, db, orderID, userID)

	// Mismatched split with financially_completed_at set → constraint violation.
	// price_total = 500, but commission (50) + driver (100) = 150 != 500.
	_, err := db.Exec(`
UPDATE orders
SET financially_completed_at = NOW(), price_total = 500, driver_amount = 100, commission_amount = 50
WHERE id = $1`, orderID)
	if err == nil {
		t.Fatal("expected chk_orders_split violation for mismatched split, got nil")
	}
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.ConstraintName != "chk_orders_split" {
		t.Fatalf("expected check constraint violation on chk_orders_split, got: %v", err)
	}

	// Correct split (100 + 400 = 500) → success.
	_, err = db.Exec(`
UPDATE orders
SET financially_completed_at = NOW(), price_total = 500, driver_amount = 400, commission_amount = 100
WHERE id = $1`, orderID)
	if err != nil {
		t.Fatalf("expected success for valid split, got: %v", err)
	}
}
