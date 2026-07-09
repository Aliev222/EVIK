//go:build integration

package postgres_test

import (
	"context"
	"testing"

	"evik/backend/internal/infrastructure/postgres"
)

// TestTrigger_RatingStats проверяет trigger_update_driver_rating_stats:
// вставка 3 отзывов → rating=4.0, reviews_count=3.
// Удаление 1 → пересчёт.
func TestTrigger_RatingStats(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "rating-driver"
	clientID := "rating-client"
	seedUser(t, db, driverID, "driver")
	seedUser(t, db, clientID, "client")
	seedDriver(t, db, driverID)

	var rating float64
	var count int
	db.QueryRow(`SELECT rating_average, rating_count FROM drivers WHERE id = $1`, driverID).Scan(&rating, &count)
	if rating != 0.0 || count != 0 {
		t.Fatalf("expected 0/0 initially, got %.2f/%d", rating, count)
	}

	order1 := "ro1-" + uuid()
	order2 := "ro2-" + uuid()
	order3 := "ro3-" + uuid()

	seedOrderRaw(t, db, order1, clientID)
	seedOrderRaw(t, db, order2, clientID)
	seedOrderRaw(t, db, order3, clientID)

	for _, oid := range []string{order1, order2, order3} {
		if _, err := db.Exec(`UPDATE orders SET driver_id = $1, status = 'completed' WHERE id = $2`, driverID, oid); err != nil {
			t.Fatalf("update order %s: %v", oid, err)
		}
	}

	if _, err := db.Exec(`INSERT INTO driver_reviews (order_id, driver_id, client_id, stars, created_at) VALUES ($1, $2, $3, 5, NOW())`, order1, driverID, clientID); err != nil {
		t.Fatalf("insert review1: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO driver_reviews (order_id, driver_id, client_id, stars, created_at) VALUES ($1, $2, $3, 4, NOW())`, order2, driverID, clientID); err != nil {
		t.Fatalf("insert review2: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO driver_reviews (order_id, driver_id, client_id, stars, created_at) VALUES ($1, $2, $3, 3, NOW())`, order3, driverID, clientID); err != nil {
		t.Fatalf("insert review3: %v", err)
	}

	err := db.QueryRow(`SELECT rating_average, rating_count FROM drivers WHERE id = $1`, driverID).Scan(&rating, &count)
	if err != nil {
		t.Fatalf("select rating: %v", err)
	}
	if count != 3 {
		t.Errorf("rating_count: expected 3, got %d", count)
	}
	if rating < 3.99 || rating > 4.01 {
		t.Errorf("rating_average: expected ~4.0, got %.2f", rating)
	}

	if _, err := db.Exec(`DELETE FROM driver_reviews WHERE order_id = $1`, order1); err != nil {
		t.Fatalf("delete review: %v", err)
	}

	err = db.QueryRow(`SELECT rating_average, rating_count FROM drivers WHERE id = $1`, driverID).Scan(&rating, &count)
	if err != nil {
		t.Fatalf("select rating after delete: %v", err)
	}
	if count != 2 {
		t.Errorf("rating_count after delete: expected 2, got %d", count)
	}
	if rating < 3.49 || rating > 3.51 {
		t.Errorf("rating_average after delete: expected 3.5, got %.2f", rating)
	}
}

func TestTrigger_SyncDriverVehicle(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "sync-veh-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	verID := "ver-" + uuid()
	if _, err := db.Exec(`
		INSERT INTO driver_verifications (id, user_id, full_name, phone, city, vehicle_model, vehicle_plate, vehicle_type, status, submitted_at, updated_at)
		VALUES ($1, $2, 'Test Driver', '7999000', 'City', 'Toyota Camry', 'A001AA', 'sedan', 'pending', NOW(), NOW())`,
		verID, driverID); err != nil {
		t.Fatalf("insert verification: %v", err)
	}

	var plate, model, vtype interface{}
	db.QueryRow(`SELECT vehicle_plate, vehicle_model, vehicle_type FROM drivers WHERE id = $1`, driverID).Scan(&plate, &model, &vtype)
	if plate != nil || model != nil || vtype != nil {
		t.Fatal("expected NULL vehicle fields before approval")
	}

	if _, err := db.Exec(`UPDATE driver_verifications SET status = 'approved', updated_at = NOW() WHERE id = $1`, verID); err != nil {
		t.Fatalf("approve verification: %v", err)
	}

	var plateS, modelS, typeS string
	if err := db.QueryRow(`SELECT COALESCE(vehicle_plate, ''), COALESCE(vehicle_model, ''), COALESCE(vehicle_type, '') FROM drivers WHERE id = $1`, driverID).Scan(&plateS, &modelS, &typeS); err != nil {
		t.Fatalf("select driver vehicle: %v", err)
	}
	if plateS != "A001AA" {
		t.Errorf("vehicle_plate: expected A001B, got %s", plateS)
	}
	if modelS != "Toyota Camry" {
		t.Errorf("vehicle_model: expected Toyota Camry, got %s", modelS)
	}
	if typeS != "sedan" {
		t.Errorf("vehicle_type: expected sedan, got %s", typeS)
	}
}

func TestFK_WalletTransactionOrder(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "fk-wallet-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	if _, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID); err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	_, err := db.Exec(`
		INSERT INTO wallet_transactions (id, wallet_id, driver_id, order_id, type, direction, amount, currency, status, description, idempotency_key, created_at)
		VALUES ($1, $2, $3, $4, 'order_income', 'credit', cents_to_rub(1000), 'RUB', 'pending', 'test', $5, NOW())`,
		"wtx-"+uuid(), "wallet_"+driverID, driverID, "nonexistent-order-id", "ik-fk-"+uuid())
	if err == nil {
		t.Fatal("expected FK violation for non-existent order_id, got nil")
	}
	t.Logf("FK error (expected): %v", err)
}

func TestFK_DriverDeleteCascade(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "fk-del-driver"
	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)

	if _, err := db.Exec(`INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
		VALUES ($1, $2, 0, 0, 0, 'RUB', NOW(), NOW())`,
		"wallet_"+driverID, driverID); err != nil {
		t.Fatalf("insert wallet: %v", err)
	}

	_, err := db.Exec(`DELETE FROM drivers WHERE id = $1`, driverID)
	if err != nil {
		t.Fatalf("expected cascade delete to succeed, got error: %v", err)
	}

	var walletCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM driver_wallets WHERE driver_id = $1`, driverID).Scan(&walletCount); err != nil {
		t.Fatalf("query wallet count: %v", err)
	}
	if walletCount != 0 {
		t.Fatalf("expected wallet to be cascade-deleted (count=0), got %d", walletCount)
	}
}

func TestGetActiveDriverSubscription(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "sub-act-driver"
	userID := "sub-act-user"
	seedUser(t, db, driverID, "driver")
	seedUser(t, db, userID, "client")
	seedDriver(t, db, driverID)

	orderID := "sub-act-order-" + uuid()
	seedOrderRaw(t, db, orderID, userID)
	if _, err := db.Exec(`UPDATE orders SET driver_id = $1, status = 'completed' WHERE id = $2`, driverID, orderID); err != nil {
		t.Fatalf("assign driver: %v", err)
	}

	payID := "pay-sub-active-" + uuid()
	if _, err := db.Exec(`INSERT INTO payments (id, order_id, user_id, provider, payment_method, purpose, amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'card', 'subscription', 50000, 'RUB', 'succeeded', $4, NOW(), NOW())`,
		payID, orderID, userID, "ik-sub-active"); err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	if _, err := db.Exec(`INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
		VALUES ($1, $2, 'plan_monthly', $3, 50000, 'RUB', 'active', NOW() - INTERVAL '60 days', NOW() - INTERVAL '30 days', NOW(), NOW())`,
		"sub-expired-"+uuid(), driverID, payID); err != nil {
		t.Fatalf("insert expired subscription: %v", err)
	}

	payID2 := "pay-sub2-" + uuid()
	if _, err := db.Exec(`INSERT INTO payments (id, order_id, user_id, provider, payment_method, purpose, amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'card', 'subscription', 50000, 'RUB', 'succeeded', $4, NOW(), NOW())`,
		payID2, orderID, userID, "ik-sub2"); err != nil {
		t.Fatalf("insert payment2: %v", err)
	}

	if _, err := db.Exec(`INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
		VALUES ($1, $2, 'plan_monthly', $3, 50000, 'RUB', 'active', NOW(), NOW() + INTERVAL '30 days', NOW(), NOW())`,
		"sub-active-"+uuid(), driverID, payID2); err != nil {
		t.Fatalf("insert active subscription: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)
	sub, err := payRepo.GetActiveDriverSubscription(context.Background(), driverID)
	if err != nil {
		t.Fatalf("GetActiveDriverSubscription: %v", err)
	}
	if sub == nil {
		t.Fatal("expected active subscription, got nil")
	}
	if sub.Status != "active" {
		t.Errorf("expected status 'active', got %s", string(sub.Status))
	}
}

func TestHasActiveSubscriptionTx(t *testing.T) {
	driverID := "sub-tx-driver"
	userID := "sub-tx-user"
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	seedUser(t, db, driverID, "driver")
	seedUser(t, db, userID, "client")
	seedDriver(t, db, driverID)

	orderID := "sub-tx-order-" + uuid()
	seedOrderRaw(t, db, orderID, userID)
	if _, err := db.Exec(`UPDATE orders SET driver_id = $1, status = 'completed' WHERE id = $2`, driverID, orderID); err != nil {
		t.Fatalf("assign driver: %v", err)
	}

	payID := "pay-sub-tx-" + uuid()
	if _, err := db.Exec(`INSERT INTO payments (id, order_id, user_id, provider, payment_method, purpose, amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'card', 'subscription', 50000, 'RUB', 'succeeded', $4, NOW(), NOW())`,
		payID, orderID, userID, "ik-sub-tx"); err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)

	err := payRepo.CompleteOrderFinancially(context.Background(), orderID, "ik-fin-sub-tx", 0, 15)
	if err != nil {
		t.Fatalf("CompleteOrderFinancially without subscription: %v", err)
	}

	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("begin tx: %v", err)
	}
	if _, err := tx.Exec(`INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
		VALUES ($1, $2, 'plan_monthly', $3, 50000, 'RUB', 'active', NOW(), NOW() + INTERVAL '30 days', NOW(), NOW())`,
		"sub-tx-"+uuid(), driverID, payID); err != nil {
		tx.Rollback()
		t.Fatalf("insert subscription in tx: %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit: %v", err)
	}
}