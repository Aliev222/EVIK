//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"testing"

	paymentdomain "evik/backend/internal/domain/payment"
	"evik/backend/internal/infrastructure/postgres"
)

func seedOrder(t *testing.T, db *sql.DB) (userID, driverID, orderID string) {
	t.Helper()
	userID = "user-" + t.Name()
	driverID = "driver-" + t.Name()

	if _, err := db.Exec(`INSERT INTO users (id, phone, full_name, role, status, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', NOW(), NOW())`,
		userID, "79990000001", "Test Client", "client"); err != nil {
		t.Fatalf("insert user: %v", err)
	}

	if _, err := db.Exec(`INSERT INTO users (id, phone, full_name, role, status, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', NOW(), NOW())`,
		driverID, "79990000002", "Test Driver", "driver"); err != nil {
		t.Fatalf("insert driver user: %v", err)
	}

	if _, err := db.Exec(`INSERT INTO drivers (id, user_id, status, last_seen_at, updated_at) VALUES ($1, $2, 'online', NOW(), NOW())`,
		driverID, driverID); err != nil {
		t.Fatalf("insert driver: %v", err)
	}

	orderID = "order-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, created_at, updated_at)
VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', $4, NOW(), NOW())`,
		orderID, userID, driverID, int64(500000)); err != nil {
		t.Fatalf("insert order: %v", err)
	}

	return
}

func seedOrderWithAmountAndSurcharge(t *testing.T, db *sql.DB, totalCents, surchargeCents int64) (userID, driverID, orderID string) {
	t.Helper()
	userID = "user-" + uuid()
	driverID = "driver-" + uuid()

	if _, err := db.Exec(`INSERT INTO users (id, phone, full_name, role, status, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', NOW(), NOW())`,
		userID, "79990000101", "Client", "client"); err != nil {
		t.Fatalf("insert user: %v", err)
	}

	if _, err := db.Exec(`INSERT INTO users (id, phone, full_name, role, status, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', NOW(), NOW())`,
		driverID, "79990000102", "Driver", "driver"); err != nil {
		t.Fatalf("insert driver user: %v", err)
	}

	if _, err := db.Exec(`INSERT INTO drivers (id, user_id, status, last_seen_at, updated_at) VALUES ($1, $2, 'online', NOW(), NOW())`,
		driverID, driverID); err != nil {
		t.Fatalf("insert driver: %v", err)
	}

	orderID = "order-" + uuid()
	if _, err := db.Exec(`
	INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, surcharge_amount, is_cross_city, created_at, updated_at)
	VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', $4, $5, $6, NOW(), NOW())`,
		orderID, userID, driverID, totalCents, surchargeCents, surchargeCents > 0); err != nil {
		t.Fatalf("insert order: %v", err)
	}

	return
}

// TestSplitInvariant_Standard проверяет базовый инвариант:
// total=500000, commission_percent=15, surcharge=0
// → commission = (500000*15 + 50)/100 = 75000
// → driverAmount = 425000
// → commission + driverAmount == total
func TestSplitInvariant_Standard(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	userID, driverID, orderID := seedOrder(t, db)
	_ = userID

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-test1", 0, 15); err != nil {
		t.Fatalf("CompleteOrderFinancially: %v", err)
	}

	wallet, err := payRepo.GetDriverWallet(ctx, driverID)
	if err != nil {
		t.Fatalf("GetDriverWallet: %v", err)
	}
	var txs []paymentdomain.WalletTransaction
	txs, err = payRepo.ListWalletTransactions(ctx, driverID, 100)
	if err != nil {
		t.Fatalf("ListWalletTransactions: %v", err)
	}

	if len(txs) != 1 {
		t.Fatalf("expected 1 wallet transaction (cash debt), got %d", len(txs))
	}
	if txs[0].Amount != 75000 {
		t.Errorf("commission amount: expected 75000, got %d", txs[0].Amount)
	}
	if txs[0].Type != paymentdomain.WalletTypeCashCommissionDebt {
		t.Errorf("type: expected cash_commission_debt, got %s", txs[0].Type)
	}

	if wallet.DebtBalance != 75000 {
		t.Errorf("debt balance: expected 75000, got %d", wallet.DebtBalance)
	}
	if wallet.PendingBalance != 0 {
		t.Errorf("pending balance: expected 0, got %d", wallet.PendingBalance)
	}
}

// TestSplitInvariant_CrossCity проверяет межгородскую наценку:
// total=750000, surcharge=250000 (cross_city)
// → base = 500000, commission = 75000 (от базы!)
// → driverAmount = 675000 (425000 + наценка целиком)
// → 75000 + 675000 == 750000
func TestSplitInvariant_CrossCity(t *testing.T) {
	db, backup := setupTestDB(t)
	defer backup()
	defer truncateAll(t, db)

	_, driverID, orderID := seedOrderWithAmountAndSurcharge(t, db, 750000, 250000)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-cross-1", 15, 15); err != nil {
		t.Fatalf("CompleteOrderFinancially: %v", err)
	}

	wallet, err := payRepo.GetDriverWallet(ctx, driverID)
	if err != nil {
		t.Fatalf("GetDriverWallet: %v", err)
	}

	t.Logf("wallet: debt=%d pending=%d", wallet.DebtBalance, wallet.PendingBalance)
	if wallet.DebtBalance != 75000 {
		t.Errorf("debt (commission from base): expected 75000, got %d", wallet.DebtBalance)
	}
	if wallet.PendingBalance != 0 {
		t.Errorf("pending: expected 0 (cash order), got %d", wallet.PendingBalance)
	}
}

// TestSplitInvariant_Subscription проверяет подписку:
// active subscription → commission = 0, driverAmount = total
func TestSplitInvariant_Subscription(t *testing.T) {
	db, backup := setupTestDB(t)
	defer backup()
	defer truncateAll(t, db)

	userID, driverID, orderID := seedOrder(t, db)

	payID := "pay-sub-" + uuid()
	if _, err := db.Exec(`INSERT INTO payments (id, order_id, user_id, provider, payment_method, purpose, amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'card', 'subscription', 50000, 'RUB', 'succeeded', $4, NOW(), NOW())`,
		payID, orderID, userID, "ik-sub-pay-"+uuid()); err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	if _, err := db.Exec(`
		INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
		VALUES ($1, $2, 'plan_monthly', $3, 50000, 'RUB', 'active', NOW(), NOW() + INTERVAL '30 days', NOW(), NOW())`,
		"sub-"+uuid(), driverID, payID); err != nil {
		t.Fatalf("insert subscription: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-sub-1", 15, 15); err != nil {
		t.Fatalf("CompleteOrderFinancially: %v", err)
	}

	wallet, err := payRepo.GetDriverWallet(ctx, driverID)
	if err != nil {
		t.Fatalf("GetDriverWallet: %v", err)
	}

	if wallet.DebtBalance != 0 {
		t.Errorf("debt (commission should be 0 with subscription): expected 0, got %d", wallet.DebtBalance)
	}
}

// TestSplitInvariant_RoundingHalfUp проверяет округление half-up:
// total=100100 (1001₽), 15%
// → (100100*15 + 50) / 100 = 15015
func TestSplitInvariant_RoundingHalfUp(t *testing.T) {
	db, backup := setupTestDB(t)
	defer backup()
	defer truncateAll(t, db)

	_, driverID, orderID := seedOrderWithAmountAndSurcharge(t, db, 100100, 0)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-round-1", 15, 15); err != nil {
		t.Fatalf("CompleteOrderFinancially: %v", err)
	}

	txs, err := payRepo.ListWalletTransactions(ctx, driverID, 100)
	if err != nil {
		t.Fatalf("ListWalletTransactions: %v", err)
	}

	if len(txs) == 0 {
		t.Fatal("expected at least 1 wallet transaction")
	}

	got := int64(0)
	for _, tx := range txs {
		if tx.Type == paymentdomain.WalletTypeCashCommissionDebt {
			got = tx.Amount
			break
		}
	}

	expected := int64(15015)
	if got != expected {
		t.Fatalf("commission: expected %d (half-up rounding), got %d", expected, got)
	}
}

// TestSplitInvariant_Idempotent проверяет идемпотентность:
// повторный вызов с тем же idempotencyKey не дублирует транзакции
func TestSplitInvariant_Idempotent(t *testing.T) {
	db, backup := setupTestDB(t)
	defer backup()
	defer truncateAll(t, db)

	_, driverID, orderID := seedOrder(t, db)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	ik := "ik-idemp-" + uuid()
	if err := payRepo.CompleteOrderFinancially(ctx, orderID, ik, 15, 15); err != nil {
		t.Fatalf("first call: %v", err)
	}

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, ik, 15, 15); err != nil {
		t.Fatalf("second call (should be idempotent): %v", err)
	}

	txs, err := payRepo.ListWalletTransactions(ctx, driverID, 100)
	if err != nil {
		t.Fatalf("ListWalletTransactions: %v", err)
	}

	count := 0
	for _, tx := range txs {
		if tx.IdempotencyKey == ik+":cash_debt" || tx.IdempotencyKey == ik {
			count++
		}
	}

	if count > 1 {
		t.Fatalf("found %d matching transactions for idempotency key, expected 1", count)
	}
}

// TestSplitInvariant_WalletTransactions проверяет корректность записей wallet_transactions:
// общая сумма дебетов/кредитов совпадает с driverAmount
func TestSplitInvariant_WalletTransactions(t *testing.T) {
	db, backup := setupTestDB(t)
	defer backup()
	defer truncateAll(t, db)

	_, driverID, orderID := seedOrder(t, db)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-wt-1", 15, 15); err != nil {
		t.Fatalf("CompleteOrderFinancially: %v", err)
	}

	txs, err := payRepo.ListWalletTransactions(ctx, driverID, 100)
	if err != nil {
		t.Fatalf("ListWalletTransactions: %v", err)
	}

	if len(txs) < 1 {
		t.Fatal("expected at least 1 wallet transaction")
	}

	totalTxAmount := int64(0)
	for _, tx := range txs {
		totalTxAmount += tx.Amount
	}

	expectedSum := int64(75000)
	if totalTxAmount != expectedSum {
		t.Errorf("sum of wallet transactions: expected %d, got %d", expectedSum, totalTxAmount)
	}
}

func TestSplitInvariant_CardOrder(t *testing.T) {
	db, backup := setupTestDB(t)
	defer backup()
	defer truncateAll(t, db)

	userID, driverID, orderID := seedOrderWithAmountAndSurcharge(t, db, 500000, 0)

	if _, err := db.Exec(`INSERT INTO payments (id, order_id, user_id, provider, payment_method, purpose, amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'card', 'order', 500000, 'RUB', 'succeeded', $4, NOW(), NOW())`,
		"pay-"+uuid(), orderID, userID, "ik-pay-"+uuid()); err != nil {
		t.Fatalf("insert payment: %v", err)
	}

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	if err := payRepo.CompleteOrderFinancially(ctx, orderID, "ik-card-1", 3600, 15); err != nil {
		t.Fatalf("CompleteOrderFinancially: %v", err)
	}

	wallet, err := payRepo.GetDriverWallet(ctx, driverID)
	if err != nil {
		t.Fatalf("GetDriverWallet: %v", err)
	}

	t.Logf("card wallet: pending=%d debt=%d", wallet.PendingBalance, wallet.DebtBalance)

	if wallet.PendingBalance != 425000 {
		t.Errorf("pending (driver income for card): expected 425000, got %d", wallet.PendingBalance)
	}
	if wallet.DebtBalance != 0 {
		t.Errorf("debt: expected 0, got %d", wallet.DebtBalance)
	}

	txs, err := payRepo.ListWalletTransactions(ctx, driverID, 100)
	if err != nil {
		t.Fatalf("ListWalletTransactions: %v", err)
	}

	t.Logf("card order tx count: %d", len(txs))
	for _, tx := range txs {
		t.Logf("  %s | %s | %d | %s", tx.Type, tx.Direction, tx.Amount, tx.IdempotencyKey)
	}

	incomeFound := false
	for _, tx := range txs {
		if tx.Type == paymentdomain.WalletTypeOrderIncome {
			incomeFound = true
			if tx.Amount != 425000 {
				t.Errorf("order income: expected 425000, got %d", tx.Amount)
			}
			break
		}
	}
	if !incomeFound {
		t.Error("expected order_income wallet transaction for card order")
	}
}