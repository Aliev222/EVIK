//go:build integration

package postgres_test

import (
	"context"
	"testing"

	paymentdomain "evik/backend/internal/domain/payment"
	"evik/backend/internal/infrastructure/postgres"
)

// TestListDebtTransactions_CashAndRepayment verifies that ListDebtTransactions
// returns the driver's cash-commission debt history (cash_commission_debt that
// built the debt and debt_repayment that reduced it), each enriched with the
// linked order total and order_id, newest first.
func TestListDebtTransactions_CashAndRepayment(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	// Cash order → builds the debt.
	userID, driverID, cashOrderID := seedOrder(t, db)
	if err := payRepo.CompleteOrderFinancially(ctx, cashOrderID, "ik-debt-cash-1", 0, 15); err != nil {
		t.Fatalf("complete cash order: %v", err)
	}

	// Card order for the same driver → repays part of the debt.
	cardOrderID := "order-card-" + uuid()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, payment_method, driver_amount, commission_amount, financially_completed_at, financial_status, created_at, updated_at)
VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', 'completed', 500000, 'card', 425000, 75000, NOW(), 'completed', NOW(), NOW())`,
		cardOrderID, userID, driverID); err != nil {
		t.Fatalf("insert card order: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO payments (id, order_id, user_id, provider, payment_method, purpose, amount, currency, status, idempotency_key, created_at, updated_at)
		VALUES ($1, $2, $3, 'yookassa', 'card', 'order', 500000, 'RUB', 'succeeded', $4, NOW(), NOW())`,
		"pay-"+uuid(), cardOrderID, userID, "ik-pay-card-1"); err != nil {
		t.Fatalf("insert card payment: %v", err)
	}
	if err := payRepo.CompleteOrderFinancially(ctx, cardOrderID, "ik-debt-card-1", 3600, 15); err != nil {
		t.Fatalf("complete card order: %v", err)
	}

	items, err := payRepo.ListDebtTransactions(ctx, driverID, 100)
	if err != nil {
		t.Fatalf("ListDebtTransactions: %v", err)
	}

	if len(items) != 2 {
		t.Fatalf("expected 2 debt transactions (1 accrued + 1 repaid), got %d", len(items))
	}

	// Newest first: the card repayment happened after the cash accrual.
	if items[0].Type != paymentdomain.WalletTypeDebtRepayment {
		t.Errorf("items[0].Type = %s, want debt_repayment (newest first)", items[0].Type)
	}
	if items[0].OrderID == nil || *items[0].OrderID != cardOrderID {
		t.Errorf("repayment order_id = %v, want %s", items[0].OrderID, cardOrderID)
	}
	if items[0].OrderAmount != 500000 {
		t.Errorf("repayment order_amount = %d, want 500000", items[0].OrderAmount)
	}
	if items[0].Amount != 75000 {
		t.Errorf("repayment amount = %d, want 75000 (commission repaid)", items[0].Amount)
	}

	if items[1].Type != paymentdomain.WalletTypeCashCommissionDebt {
		t.Errorf("items[1].Type = %s, want cash_commission_debt", items[1].Type)
	}
	if items[1].OrderID == nil || *items[1].OrderID != cashOrderID {
		t.Errorf("cash debt order_id = %v, want %s", items[1].OrderID, cashOrderID)
	}
	if items[1].OrderAmount != 500000 {
		t.Errorf("cash debt order_amount = %d, want 500000", items[1].OrderAmount)
	}
	if items[1].Amount != 75000 {
		t.Errorf("cash debt amount = %d, want 75000", items[1].Amount)
	}
}

// TestListDebtTransactions_OnlyOwnDriver verifies that ListDebtTransactions
// never returns another driver's debt transactions: the query is scoped to the
// requesting driver_id.
func TestListDebtTransactions_OnlyOwnDriver(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	payRepo := postgres.NewPaymentRepository(db)
	ctx := context.Background()

	// Driver A builds debt.
	_, driverA, orderA := seedOrder(t, db)
	if err := payRepo.CompleteOrderFinancially(ctx, orderA, "ik-debt-a-1", 0, 15); err != nil {
		t.Fatalf("complete driver A cash order: %v", err)
	}

	// Driver B has no debt transactions at all.
	items, err := payRepo.ListDebtTransactions(ctx, "driver-B", 100)
	if err != nil {
		t.Fatalf("ListDebtTransactions for driver B: %v", err)
	}
	if len(items) != 0 {
		t.Fatalf("driver B must not see driver A's debt transactions, got %d", len(items))
	}

	// And driver A still sees their own.
	itemsA, err := payRepo.ListDebtTransactions(ctx, driverA, 100)
	if err != nil {
		t.Fatalf("ListDebtTransactions for driver A: %v", err)
	}
	if len(itemsA) != 1 || itemsA[0].Type != paymentdomain.WalletTypeCashCommissionDebt {
		t.Fatalf("driver A expected 1 cash_commission_debt, got %#v", itemsA)
	}
}
