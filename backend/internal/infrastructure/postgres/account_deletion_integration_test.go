//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	"evik/backend/internal/domain/user"
	"evik/backend/internal/infrastructure/postgres"
	acc "evik/backend/internal/usecase/account"
)

func insertActiveOrder(t *testing.T, db *sql.DB, id, userID, driverID, status string) {
	t.Helper()
	var driverRef any
	if driverID != "" {
		driverRef = driverID
	}
	financialStatus := "pending"
	var financialCompleted any
	var driverAmount int64
	var commissionAmount int64
	if status == "completed" {
		financialCompleted = time.Now()
		financialStatus = "completed"
		driverAmount = 500000
	}
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, financial_status, financially_completed_at, driver_amount, commission_amount, created_at, updated_at)
VALUES ($1, $2, $3, 42.0, 47.5, 42.1, 47.6, 'winch', $4, 500000, $6, $5, $7, $8, NOW(), NOW())`,
		id, userID, driverRef, status, financialCompleted, financialStatus, driverAmount, commissionAmount); err != nil {
		t.Fatalf("insert order %s: %v", id, err)
	}
}

func insertPaymentMethod(t *testing.T, db *sql.DB, id, userID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO payment_methods (id, user_id, provider, provider_payment_method_id, brand, last4, exp_month, exp_year, holder, status, is_default, created_at)
VALUES ($1, $2, 'yookassa', 'pm_123', 'VISA', '4242', 12, 2030, 'HOLDER', 'active', FALSE, NOW())`, id, userID); err != nil {
		t.Fatalf("insert payment method: %v", err)
	}
}

func insertRefreshSession(t *testing.T, db *sql.DB, id, userID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO user_refresh_sessions (id, user_id, role, token_hash, expires_at, created_at)
VALUES ($1, $2, 'client', $3, NOW() + INTERVAL '1 day', NOW())`, id, userID, "hash-"+id); err != nil {
		t.Fatalf("insert refresh session: %v", err)
	}
}

func insertDeviceToken(t *testing.T, db *sql.DB, id, userID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO user_device_tokens (fcm_token, user_id, role, platform, app_version, created_at, updated_at)
VALUES ($1, $2, 'client', 'android', '1.0', NOW(), NOW())`, "fcm-"+id, userID); err != nil {
		t.Fatalf("insert device token: %v", err)
	}
}

func insertWallet(t *testing.T, db *sql.DB, userID string, available int64) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
VALUES ($1, $2, $3, 0, 0, 'RUB', NOW(), NOW())`, "wallet-"+userID, userID, available); err != nil {
		t.Fatalf("insert wallet: %v", err)
	}
}

func insertTaxProfile(t *testing.T, db *sql.DB, driverID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO driver_tax_profiles (driver_id, inn, taxpayer_type, verification_status, npd_connection_status, created_at, updated_at)
VALUES ($1, '123456789012', 'self_employed', 'verified', 'connected', NOW(), NOW())`, driverID); err != nil {
		t.Fatalf("insert tax profile: %v", err)
	}
}

func insertVerification(t *testing.T, db *sql.DB, driverID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO driver_verifications (id, user_id, full_name, phone, city, vehicle_model, vehicle_plate, vehicle_type, status, documents_json, signals_json, submitted_at, updated_at)
VALUES ($1, $2, 'Иван Петров', '+79990001122', 'Москва', 'Volvo', 'A123BC', 'platform', 'approved', '[{"type":"passport","url":"s3://doc.svg"}]', '[]', NOW(), NOW())`,
		"verif-"+driverID, driverID); err != nil {
		t.Fatalf("insert verification: %v", err)
	}
}

func insertDocument(t *testing.T, db *sql.DB, verificationID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO driver_documents (verification_id, document_type, storage_key, public_url, content_type, file_size_bytes, uploaded_at)
VALUES ($1, 'passport', 's3://key/passport.jpeg', 'https://cdn/x/passport.jpeg', 'image/jpeg', 1024, NOW())`, verificationID); err != nil {
		t.Fatalf("insert document: %v", err)
	}
}

func insertPayoutMethod(t *testing.T, db *sql.DB, driverID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO driver_payout_methods (id, driver_id, provider_recipient_id, type, masked_value, is_default, status, created_at)
VALUES ($1, $2, 'recp-123', 'bank_card', '2200 **** 0000', FALSE, 'active', NOW())`, "pm-"+driverID, driverID); err != nil {
		t.Fatalf("insert payout method: %v", err)
	}
}

func TestDeleteClientAccountAnonymizesAndRetainsFinancials(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	seedUser(t, db, "client-1", "client")
	insertActiveOrder(t, db, "order-finished", "client-1", "", "completed")
	insertPaymentMethod(t, db, "pm-1", "client-1")
	insertRefreshSession(t, db, "rs-1", "client-1")
	insertDeviceToken(t, db, "dt-1", "client-1")

	var oldPhone string
	if err := db.QueryRow(`SELECT phone FROM users WHERE id='client-1'`).Scan(&oldPhone); err != nil {
		t.Fatalf("load old phone: %v", err)
	}

	uc := acc.NewUseCase(postgres.NewAccountRepository(db))
	if err := uc.Execute(ctx, "client-1", auth.RoleClient); err != nil {
		t.Fatalf("delete client account: %v", err)
	}

	// Identity anonymized + login disabled.
	var status string
	var deletedAt *time.Time
	var phone string
	if err := db.QueryRow(`SELECT status, deleted_at, phone FROM users WHERE id='client-1'`).Scan(&status, &deletedAt, &phone); err != nil {
		t.Fatalf("load deleted user: %v", err)
	}
	if status != "deleted" || deletedAt == nil {
		t.Fatalf("user not marked deleted: status=%q deleted_at=%v", status, deletedAt)
	}
	if !strings.HasPrefix(phone, "deleted:") {
		t.Fatalf("phone was not anonymized to deleted:<id>, got %q", phone)
	}

	count := func(q string) int {
		var n int
		if err := db.QueryRow(q).Scan(&n); err != nil {
			t.Fatalf("count query %q: %v", q, err)
		}
		return n
	}
	if c := count(`SELECT COUNT(*) FROM user_refresh_sessions WHERE user_id='client-1'`); c != 0 {
		t.Fatalf("refresh sessions not deleted: %d", c)
	}
	if c := count(`SELECT COUNT(*) FROM user_device_tokens WHERE user_id='client-1'`); c != 0 {
		t.Fatalf("device tokens not deleted: %d", c)
	}
	if c := count(`SELECT COUNT(*) FROM payment_methods WHERE user_id='client-1'`); c != 0 {
		t.Fatalf("payment methods not deleted: %d", c)
	}
	if c := count(`SELECT COUNT(*) FROM orders WHERE user_id='client-1' AND id='order-finished'`); c != 1 {
		t.Fatalf("finished order was deleted: %d", c)
	}

	// Login blocked and phone freed.
	userRepo := postgres.NewUserRepository(db)
	active, err := userRepo.IsUserActive(ctx, "client-1")
	if err != nil || active {
		t.Fatalf("IsUserActive after deletion = %v (err=%v), want false", active, err)
	}
	if _, err := userRepo.GetByPhoneAndRole(ctx, oldPhone, "client"); err == nil || !errors.Is(err, user.ErrUserNotFound) {
		t.Fatalf("old phone still resolves to deleted user: %v", err)
	}
}

func TestDeleteClientBlockedByActiveOrder(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	seedUser(t, db, "client-1", "client")
	insertActiveOrder(t, db, "order-active", "client-1", "", "searching")

	uc := acc.NewUseCase(postgres.NewAccountRepository(db))
	err := uc.Execute(context.Background(), "client-1", auth.RoleClient)
	if !errors.Is(err, acc.ErrActiveOrder) {
		t.Fatalf("expected ErrActiveOrder, got %v", err)
	}

	var status string
	if err := db.QueryRow(`SELECT status FROM users WHERE id='client-1'`).Scan(&status); err != nil {
		t.Fatalf("load user: %v", err)
	}
	if status != "active" {
		t.Fatalf("user was changed despite active-order guard: %s", status)
	}
}

func TestDeleteDriverAccountRetainsWalletAndStripsPII(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	seedUser(t, db, "driver-1", "driver")
	seedDriver(t, db, "driver-1")
	insertWallet(t, db, "driver-1", 0)
	insertTaxProfile(t, db, "driver-1")
	insertVerification(t, db, "driver-1")
	insertDocument(t, db, "verif-driver-1")
	insertPayoutMethod(t, db, "driver-1")

	uc := acc.NewUseCase(postgres.NewAccountRepository(db))
	if err := uc.Execute(ctx, "driver-1", auth.RoleDriver); err != nil {
		t.Fatalf("delete driver account: %v", err)
	}

	var vehicleModel, drvStatus string
	if err := db.QueryRow(`SELECT vehicle_model, status FROM drivers WHERE id='driver-1'`).Scan(&vehicleModel, &drvStatus); err != nil {
		t.Fatalf("load driver: %v", err)
	}
	if vehicleModel == "" || drvStatus != "offline" {
		t.Fatalf("driver not anonymized: vehicle_model=%q status=%q", vehicleModel, drvStatus)
	}

	var vName, vPhone, vDocJSON string
	if err := db.QueryRow(`SELECT full_name, phone, documents_json FROM driver_verifications WHERE id='verif-driver-1'`).Scan(&vName, &vPhone, &vDocJSON); err != nil {
		t.Fatalf("load verification: %v", err)
	}
	if vName == "Иван Петров" || vPhone != "" || vDocJSON != "[]" {
		t.Fatalf("verification PII not stripped: name=%q phone=%q docs=%q", vName, vPhone, vDocJSON)
	}

	var docCount, pmCount, walletCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM driver_documents WHERE verification_id='verif-driver-1'`).Scan(&docCount); err != nil {
		t.Fatalf("count docs: %v", err)
	}
	if docCount != 0 {
		t.Fatalf("driver documents not deleted: %d", docCount)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM driver_payout_methods WHERE driver_id='driver-1'`).Scan(&pmCount); err != nil {
		t.Fatalf("count payout methods: %v", err)
	}
	if pmCount != 0 {
		t.Fatalf("payout methods not deleted: %d", pmCount)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM driver_wallets WHERE driver_id='driver-1'`).Scan(&walletCount); err != nil {
		t.Fatalf("count wallets: %v", err)
	}
	if walletCount != 1 {
		t.Fatalf("wallet financial record was deleted: %d", walletCount)
	}

	// Tax profile retained with INN; NPD credentials revoked.
	var inn, npdStatus string
	var npdTok *string
	if err := db.QueryRow(`SELECT inn, npd_connection_status, npd_access_token FROM driver_tax_profiles WHERE driver_id='driver-1'`).Scan(&inn, &npdStatus, &npdTok); err != nil {
		t.Fatalf("load tax profile: %v", err)
	}
	if inn != "123456789012" || npdStatus != "revoked" {
		t.Fatalf("tax profile mishandled: inn=%q npd=%q", inn, npdStatus)
	}
	if npdTok != nil {
		t.Fatalf("NPD access token was not revoked")
	}
}

func TestDeleteDriverBlockedByActiveOrder(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	seedUser(t, db, "client-1", "client")
	seedUser(t, db, "driver-1", "driver")
	seedDriver(t, db, "driver-1")
	insertActiveOrder(t, db, "order-active", "client-1", "driver-1", "accepted")

	uc := acc.NewUseCase(postgres.NewAccountRepository(db))
	err := uc.Execute(context.Background(), "driver-1", auth.RoleDriver)
	if !errors.Is(err, acc.ErrActiveOrder) {
		t.Fatalf("expected ErrActiveOrder, got %v", err)
	}
}

func TestDeleteDriverBlockedByOutstandingBalance(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	seedUser(t, db, "driver-1", "driver")
	seedDriver(t, db, "driver-1")
	insertWallet(t, db, "driver-1", 1000)

	uc := acc.NewUseCase(postgres.NewAccountRepository(db))
	err := uc.Execute(context.Background(), "driver-1", auth.RoleDriver)
	if !errors.Is(err, acc.ErrOutstandingDriverBalance) {
		t.Fatalf("expected ErrOutstandingDriverBalance, got %v", err)
	}

	var status string
	if err := db.QueryRow(`SELECT status FROM users WHERE id='driver-1'`).Scan(&status); err != nil {
		t.Fatalf("load user: %v", err)
	}
	if status != "active" {
		t.Fatalf("user was changed despite balance guard: %s", status)
	}
}