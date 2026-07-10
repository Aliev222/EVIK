//go:build integration

package postgres_test

import (
	"testing"
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
	if err.Error() != `pq: new row for relation "orders" violates check constraint "chk_orders_completed_financially"` {
		t.Fatalf("unexpected error: %v", err)
	}

	_, err = db.Exec(`UPDATE orders SET status = 'completed', financially_completed_at = NOW() WHERE id = $1`, orderID)
	if err != nil {
		t.Fatalf("expected success when completing order with financially_completed_at, got: %v", err)
	}
}
