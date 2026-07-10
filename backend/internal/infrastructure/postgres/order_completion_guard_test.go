//go:build integration

package postgres_test

import (
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

func TestOrderCannotBeCompletedWithoutFinancialClosure(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	userID := "user-" + uuid()
	seedUser(t, db, userID, "client")

	orderID := "order-" + uuid()
	seedOrderRaw(t, db, orderID, userID)

	_, err := db.Exec(`UPDATE orders SET status = 'completed' WHERE id = $1`, orderID)
	if err == nil {
		t.Fatal("expected constraint violation when completing order without financially_completed_at, got nil")
	}
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.ConstraintName != "chk_orders_completed_financially" {
		t.Fatalf("expected check constraint violation on chk_orders_completed_financially, got: %v", err)
	}

	_, err = db.Exec(`UPDATE orders SET status = 'completed', financially_completed_at = NOW() WHERE id = $1`, orderID)
	if err != nil {
		t.Fatalf("expected success when completing order with financially_completed_at, got: %v", err)
	}
}
