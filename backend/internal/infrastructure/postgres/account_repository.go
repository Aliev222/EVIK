package postgres

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"time"

	"evik/backend/internal/auth"
	acc "evik/backend/internal/usecase/account"
)

// activeOrderStatuses are non-terminal order statuses that block account
// deletion for both the client and the driver side of an order.
const activeOrderStatuses = "('searching','accepted','arrived','in_progress','awaiting_payment')"

// AccountRepository deletes (anonymizes + deactivates) a user's own account.
// All guard checks and mutations run in a single transaction.
type AccountRepository struct {
	db *sql.DB
}

func NewAccountRepository(db *sql.DB) *AccountRepository {
	return &AccountRepository{db: db}
}

func (r *AccountRepository) Delete(ctx context.Context, userID string, role auth.Role, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Lock the user row first so a concurrent order assignment or payout
	// cannot slip in between the guards and the anonymization.
	var phone string
	err = tx.QueryRowContext(ctx, `SELECT phone FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&phone)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return acc.ErrAccountNotFound
		}
		return err
	}

	// Guard 1: no active order as a client.
	var activeClientOrder bool
	if err := tx.QueryRowContext(ctx, `
SELECT EXISTS(SELECT 1 FROM orders WHERE user_id = $1 AND status IN `+activeOrderStatuses+`)`,
		userID,
	).Scan(&activeClientOrder); err != nil {
		return err
	}
	if activeClientOrder {
		return acc.ErrActiveOrder
	}

	// A driver may additionally be referenced by drivers / driver_wallets.
	var isDriver bool
	if err := tx.QueryRowContext(ctx, `
SELECT EXISTS(SELECT 1 FROM drivers WHERE user_id = $1 OR id = $1)`, userID,
	).Scan(&isDriver); err != nil {
		return err
	}

	if isDriver {
		// Guard 2: no active order as a driver.
		var activeDriverOrder bool
		if err := tx.QueryRowContext(ctx, `
SELECT EXISTS(SELECT 1 FROM orders WHERE driver_id = $1 AND status IN `+activeOrderStatuses+`)`,
			userID,
		).Scan(&activeDriverOrder); err != nil {
			return err
		}
		if activeDriverOrder {
			return acc.ErrActiveOrder
		}

		// Guard 3: no outstanding wallet balances.
		var available, pending, debt int64
		err := tx.QueryRowContext(ctx, `
SELECT available_balance, pending_balance, debt_balance
FROM driver_wallets WHERE driver_id = $1`, userID,
		).Scan(&available, &pending, &debt)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		if err == nil && (available != 0 || pending != 0 || debt != 0) {
			return acc.ErrOutstandingDriverBalance
		}
	}

	ansiPhone := "deleted:" + userID + ":" + strconv.FormatInt(now.UnixMilli(), 10)
	// Anonymize the identity and disable login. Refresh/access tokens are
	// invalidated by the auth middleware via status + deleted_at, and the
	// original phone is freed for a brand-new account on re-registration.
	if _, err := tx.ExecContext(ctx, `
UPDATE users
SET phone = $2,
    full_name = 'Удалённый пользователь',
    status = 'deleted',
    password_hash = NULL,
    fns_full_name = NULL,
    deleted_at = $3,
    updated_at = $3
WHERE id = $1`, userID, ansiPhone, now); err != nil {
		return err
	}

	// Revoke every credential: refresh sessions, push tokens, OTPs for the
	// old phone, and locally stored payment methods.
	if _, err := tx.ExecContext(ctx, `DELETE FROM user_refresh_sessions WHERE user_id = $1`, userID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM user_device_tokens WHERE user_id = $1`, userID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM phone_otps WHERE phone = $1`, phone); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM payment_methods WHERE user_id = $1`, userID); err != nil {
		return err
	}

	if isDriver {
		if err := r.deleteDriverPII(ctx, tx, userID, now); err != nil {
			return err
		}
	}

	return tx.Commit()
}

// deleteDriverPII anonymizes driver records while keeping the rows that back
// financial/legal reporting (driver_wallets, payouts, wallet_transactions,
// subscriptions, driver_tax_profiles). Credentials and recipient detail are
// wiped.
func (r *AccountRepository) deleteDriverPII(ctx context.Context, tx *sql.Tx, userID string, now time.Time) error {
	if _, err := tx.ExecContext(ctx, `
UPDATE drivers
SET status = 'offline',
    current_order_id = NULL,
    vehicle_plate = '',
    vehicle_model = 'Удалённый водитель',
    vehicle_type = '',
    updated_at = $2
WHERE user_id = $1 OR id = $1`, userID, now); err != nil {
		return err
	}

	// Verification rows are retained for audit, but their PII is stripped.
	if _, err := tx.ExecContext(ctx, `
UPDATE driver_verifications
SET full_name = 'Удалённый водитель',
    phone = '',
    city = '',
    vehicle_model = '',
    vehicle_plate = '',
    vehicle_type = '',
    admin_comments = '',
    documents_json = '[]',
    signals_json = '[]',
    updated_at = $2
WHERE user_id = $1 OR id = $1`, userID, now); err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
DELETE FROM driver_documents
WHERE verification_id IN (SELECT id FROM driver_verifications WHERE user_id = $1 OR id = $1)`, userID); err != nil {
		return err
	}

	// NPD / Moy Nalog credentials are revoked; the INN stays for tax audit.
	if _, err := tx.ExecContext(ctx, `
UPDATE driver_tax_profiles
SET npd_access_token = NULL,
    npd_refresh_token = NULL,
    npd_token_expires_at = NULL,
    npd_revoked_at = $2,
    npd_connection_status = 'revoked',
    updated_at = $2
WHERE driver_id = $1`, userID, now); err != nil {
		return err
	}

	// Payout recipient detail (masked_value / provider_recipient_id) is PII.
	if _, err := tx.ExecContext(ctx, `DELETE FROM driver_payout_methods WHERE driver_id = $1`, userID); err != nil {
		return err
	}
	return nil
}