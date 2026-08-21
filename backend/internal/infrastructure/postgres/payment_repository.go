package postgres

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

const defaultCommissionPercent = 15

type PaymentRepository struct {
	db *sql.DB
}

func NewPaymentRepository(db *sql.DB) *PaymentRepository {
	return &PaymentRepository{db: db}
}

func (r *PaymentRepository) ListMethods(ctx context.Context, userID string) ([]paymentdomain.PaymentMethod, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, user_id, provider, provider_payment_method_id, provider_payment_id, brand, last4, exp_month, exp_year, holder, status, is_default, created_at
FROM payment_methods
WHERE user_id = $1
AND status = 'active'
ORDER BY is_default DESC, created_at DESC
`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	methods := make([]paymentdomain.PaymentMethod, 0)
	for rows.Next() {
		var method paymentdomain.PaymentMethod
		var provider, brand string
		var providerPaymentMethodID, providerPaymentID sql.NullString
		if err := rows.Scan(
			&method.ID,
			&method.UserID,
			&provider,
			&providerPaymentMethodID,
			&providerPaymentID,
			&brand,
			&method.Last4,
			&method.ExpMonth,
			&method.ExpYear,
			&method.Holder,
			&method.Status,
			&method.IsDefault,
			&method.CreatedAt,
		); err != nil {
			return nil, err
		}
		method.Provider = paymentdomain.PaymentProvider(provider)
		method.ProviderPaymentMethodID = nullableString(providerPaymentMethodID)
		method.ProviderPaymentID = nullableString(providerPaymentID)
		method.Brand = paymentdomain.CardBrand(brand)
		methods = append(methods, method)
	}
	return methods, rows.Err()
}

func (r *PaymentRepository) AddMethod(ctx context.Context, method paymentdomain.PaymentMethod) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var count int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_methods WHERE user_id = $1 AND status = 'active'`, method.UserID).Scan(&count); err != nil {
		return err
	}
	if method.Provider == "" {
		method.Provider = paymentdomain.ProviderYooKassa
	}
	if method.Status == "" {
		method.Status = "active"
	}
	isDefault := method.IsDefault || count == 0
	if isDefault {
		if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = FALSE WHERE user_id = $1 AND status = 'active'`, method.UserID); err != nil {
			return err
		}
	}

	_, err = tx.ExecContext(ctx, `
INSERT INTO payment_methods (id, user_id, provider, provider_payment_method_id, provider_payment_id, brand, last4, exp_month, exp_year, holder, status, is_default, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
`, method.ID, method.UserID, string(method.Provider), method.ProviderPaymentMethodID, method.ProviderPaymentID, string(method.Brand), method.Last4, method.ExpMonth, method.ExpYear, method.Holder, method.Status, isDefault, method.CreatedAt)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) CreatePendingPaymentMethod(ctx context.Context, p *paymentdomain.Payment, method paymentdomain.PaymentMethod) (*paymentdomain.AddCardInit, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if method.Provider == "" {
		method.Provider = paymentdomain.ProviderYooKassa
	}
	if method.Status == "" {
		method.Status = "pending"
	}
	_, err = tx.ExecContext(ctx, `
INSERT INTO payment_methods (id, user_id, provider, provider_payment_method_id, provider_payment_id, brand, last4, exp_month, exp_year, holder, status, is_default, created_at)
VALUES ($1, $2, $3, NULL, $4, $5, $6, $7, $8, $9, $10, FALSE, $11)
ON CONFLICT (id) DO UPDATE SET provider_payment_id = EXCLUDED.provider_payment_id
`, method.ID, method.UserID, string(method.Provider), method.ProviderPaymentID, string(method.Brand), method.Last4, method.ExpMonth, method.ExpYear, method.Holder, method.Status, method.CreatedAt)
	if err != nil {
		return nil, err
	}
	created, err := scanPayment(tx.QueryRowContext(ctx, `
INSERT INTO payments (
	id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at
)
VALUES ($1, NULL, NULL, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NULL, $12, $13)
ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = payments.updated_at
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
		p.ID, p.UserID, string(p.Provider), p.ProviderPaymentID, string(p.PaymentMethod), string(p.Purpose),
		p.Amount, p.Currency, string(p.Status), p.ConfirmationURL, p.IdempotencyKey, p.CreatedAt, p.UpdatedAt))
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	confirmationURL := ""
	if created.ConfirmationURL != nil {
		confirmationURL = *created.ConfirmationURL
	}
	return &paymentdomain.AddCardInit{
		PaymentMethodID: method.ID,
		ConfirmationURL: confirmationURL,
	}, nil
}

func (r *PaymentRepository) SetDefaultMethod(ctx context.Context, userID string, methodID string) (*paymentdomain.PaymentMethod, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var exists bool
	if err := tx.QueryRowContext(ctx, `
SELECT EXISTS(SELECT 1 FROM payment_methods WHERE id = $1 AND user_id = $2 AND status = 'active')
`, methodID, userID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, paymentdomain.ErrPaymentMethodNotFound
	}

	if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = FALSE WHERE user_id = $1 AND status = 'active'`, userID); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = TRUE WHERE id = $1 AND user_id = $2 AND status = 'active'`, methodID, userID); err != nil {
		return nil, err
	}

	var method paymentdomain.PaymentMethod
	var provider, brand string
	var providerPaymentMethodID, providerPaymentID sql.NullString
	err = tx.QueryRowContext(ctx, `
SELECT id, user_id, provider, provider_payment_method_id, provider_payment_id, brand, last4, exp_month, exp_year, holder, status, is_default, created_at
FROM payment_methods
WHERE id = $1 AND user_id = $2
`, methodID, userID).Scan(
		&method.ID,
		&method.UserID,
		&provider,
		&providerPaymentMethodID,
		&providerPaymentID,
		&brand,
		&method.Last4,
		&method.ExpMonth,
		&method.ExpYear,
		&method.Holder,
		&method.Status,
		&method.IsDefault,
		&method.CreatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentMethodNotFound
	}
	if err != nil {
		return nil, err
	}
	method.Provider = paymentdomain.PaymentProvider(provider)
	method.ProviderPaymentMethodID = nullableString(providerPaymentMethodID)
	method.ProviderPaymentID = nullableString(providerPaymentID)
	method.Brand = paymentdomain.CardBrand(brand)
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &method, nil
}

func (r *PaymentRepository) DeleteMethod(ctx context.Context, userID string, methodID string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var wasDefault bool
	err = tx.QueryRowContext(ctx, `
SELECT is_default FROM payment_methods WHERE id = $1 AND user_id = $2 AND status = 'active'
`, methodID, userID).Scan(&wasDefault)
	if errors.Is(err, sql.ErrNoRows) {
		return paymentdomain.ErrPaymentMethodNotFound
	}
	if err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
DELETE FROM payment_methods WHERE id = $1 AND user_id = $2
`, methodID, userID); err != nil {
		return err
	}

	if wasDefault {
		if _, err := tx.ExecContext(ctx, `
UPDATE payment_methods
SET is_default = TRUE
WHERE id = (
	SELECT id FROM payment_methods
	WHERE user_id = $1
	AND status = 'active'
	ORDER BY created_at DESC
	LIMIT 1
)
`, userID); err != nil {
			return err
		}
	}

	return tx.Commit()
}

func (r *PaymentRepository) ListClientPayments(ctx context.Context, userID string, limit int, offset int) ([]paymentdomain.PaymentTransaction, error) {
	if limit <= 0 {
		limit = 20
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT p.id, p.user_id, COALESCE(p.order_id, ''), COALESCE('Заказ №' || p.order_id, 'Оплата'), p.amount, p.status, COALESCE(p.paid_at, p.created_at)
FROM payments p
LEFT JOIN orders o ON o.id = p.order_id
WHERE p.user_id = $1
AND p.purpose = 'order'
ORDER BY COALESCE(p.paid_at, p.created_at) DESC
LIMIT $2 OFFSET $3
`, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	transactions := make([]paymentdomain.PaymentTransaction, 0)
	for rows.Next() {
		var transaction paymentdomain.PaymentTransaction
		if err := rows.Scan(
			&transaction.ID,
			&transaction.UserID,
			&transaction.OrderID,
			&transaction.Title,
			&transaction.Amount,
			&transaction.Status,
			&transaction.CreatedAt,
		); err != nil {
			return nil, err
		}
		transactions = append(transactions, transaction)
	}
	return transactions, rows.Err()
}

func (r *PaymentRepository) CreateOrderPayment(ctx context.Context, p *paymentdomain.Payment) (*paymentdomain.Payment, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	const query = `
INSERT INTO payments (
	id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = payments.updated_at
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`
	created, err := scanPayment(tx.QueryRowContext(ctx, query,
		p.ID, p.OrderID, p.DriverID, p.UserID, string(p.Provider), p.ProviderPaymentID, string(p.PaymentMethod), string(p.Purpose),
		p.Amount, p.Currency, string(p.Status), p.ConfirmationURL, p.IdempotencyKey, p.PaidAt, p.CreatedAt, p.UpdatedAt,
	))
	if err != nil {
		return nil, err
	}
	if p.OrderID != nil {
		if _, err := tx.ExecContext(ctx, `UPDATE orders SET price_total = $1, payment_method = $2, updated_at = NOW() WHERE id = $3`, p.Amount, string(p.PaymentMethod), *p.OrderID); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return created, nil
}

func (r *PaymentRepository) AttachProviderPayment(ctx context.Context, paymentID, providerPaymentID, status string, confirmationURL *string, paidAt *time.Time) (*paymentdomain.Payment, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	updated, err := scanPayment(tx.QueryRowContext(ctx, `
UPDATE payments
SET provider_payment_id = $2, status = $3, confirmation_url = $4, paid_at = COALESCE($5, paid_at), updated_at = NOW()
WHERE id = $1
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
		paymentID, providerPaymentID, status, confirmationURL, paidAt))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentNotFound
	}
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return updated, nil
}

func (r *PaymentRepository) AttachPaymentMethodProvider(ctx context.Context, methodID, providerPaymentID string) error {
	res, err := r.db.ExecContext(ctx, `UPDATE payment_methods SET provider_payment_id = $2 WHERE id = $1`, methodID, providerPaymentID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return paymentdomain.ErrPaymentMethodNotFound
	}
	return nil
}

func (r *PaymentRepository) CreateSubscriptionPayment(ctx context.Context, p *paymentdomain.Payment, s *paymentdomain.Subscription) (*paymentdomain.Payment, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	created, err := scanPayment(tx.QueryRowContext(ctx, `
INSERT INTO payments (
	id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at
)
VALUES ($1, NULL, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NULL, $13, $14)
ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = payments.updated_at
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
		p.ID, p.DriverID, p.UserID, string(p.Provider), p.ProviderPaymentID, string(p.PaymentMethod), string(p.Purpose),
		p.Amount, p.Currency, string(p.Status), p.ConfirmationURL, p.IdempotencyKey, p.CreatedAt, p.UpdatedAt,
	))
	if err != nil {
		return nil, err
	}
	_, err = tx.ExecContext(ctx, `
INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
ON CONFLICT (payment_id) DO NOTHING`,
		s.ID, s.DriverID, s.PlanID, created.ID, s.Amount, s.Currency, string(s.Status), s.StartsAt, s.EndsAt, s.CreatedAt, s.UpdatedAt)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return created, nil
}

func (r *PaymentRepository) GetPayment(ctx context.Context, paymentID string) (*paymentdomain.Payment, error) {
	p, err := scanPayment(r.db.QueryRowContext(ctx, paymentSelectSQL()+` WHERE id = $1`, paymentID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentNotFound
	}
	return p, err
}

func (r *PaymentRepository) GetPaymentByOrderID(ctx context.Context, orderID string) (*paymentdomain.Payment, error) {
	p, err := scanPayment(r.db.QueryRowContext(ctx, paymentSelectSQL()+` WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1`, orderID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentNotFound
	}
	return p, err
}

func (r *PaymentRepository) UpdatePaymentFromProvider(ctx context.Context, providerPaymentID, status string, paid bool) (*paymentdomain.Payment, error) {
	var paidAt any
	if paid {
		paidAt = time.Now().UTC()
	}
	p, err := scanPayment(r.db.QueryRowContext(ctx, `
UPDATE payments
SET status = $2, paid_at = COALESCE($3, paid_at), updated_at = NOW()
WHERE provider_payment_id = $1
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
		providerPaymentID, status, paidAt))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentNotFound
	}
	return p, err
}

func (r *PaymentRepository) StoreWebhook(ctx context.Context, eventID, provider, eventType string, payload []byte) (bool, error) {
	var inserted bool
	err := r.db.QueryRowContext(ctx, `
INSERT INTO payment_webhooks (id, provider, event_type, payload, processed, created_at)
VALUES ($1, $2, $3, $4, FALSE, NOW())
ON CONFLICT (id) DO NOTHING
RETURNING TRUE`, eventID, provider, eventType, string(payload)).Scan(&inserted)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return inserted, err
}

func (r *PaymentRepository) MarkWebhookProcessed(ctx context.Context, eventID string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE payment_webhooks SET processed = TRUE, processed_at = NOW() WHERE id = $1`, eventID)
	return err
}

func (r *PaymentRepository) ActivatePaymentMethodFromProvider(ctx context.Context, providerPaymentID, providerPaymentMethodID, brand, last4 string, expMonth, expYear int, holder string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := r.activatePaymentMethodFromProviderTx(ctx, tx, providerPaymentID, providerPaymentMethodID, brand, last4, expMonth, expYear, holder); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) activatePaymentMethodFromProviderTx(ctx context.Context, tx *sql.Tx, providerPaymentID, providerPaymentMethodID, brand, last4 string, expMonth, expYear int, holder string) error {
	var userID string
	var methodID string
	if err := tx.QueryRowContext(ctx, `
SELECT user_id, id
FROM payment_methods
WHERE provider_payment_id = $1
FOR UPDATE
`, providerPaymentID).Scan(&userID, &methodID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return paymentdomain.ErrPaymentMethodNotFound
		}
		return err
	}

	var activeCount int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_methods WHERE user_id = $1 AND status = 'active'`, userID).Scan(&activeCount); err != nil {
		return err
	}
	isDefault := activeCount == 0
	if isDefault {
		if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = FALSE WHERE user_id = $1`, userID); err != nil {
			return err
		}
	}
	cardBrand := normalizeProviderBrand(brand)
	if last4 == "" {
		last4 = "0000"
	}
	if holder == "" {
		holder = "Bank card *" + last4
	}
	_, err := tx.ExecContext(ctx, `
UPDATE payment_methods
SET provider_payment_method_id = $2,
	brand = $3,
	last4 = $4,
	exp_month = $5,
	exp_year = $6,
	holder = $7,
	status = 'active',
	is_default = CASE WHEN $8 THEN TRUE ELSE is_default END
WHERE id = $1
`, methodID, providerPaymentMethodID, string(cardBrand), last4, expMonth, expYear, holder, isDefault)
	if err != nil {
		return err
	}
	return nil
}

func (r *PaymentRepository) CompleteOrderFinancially(ctx context.Context, orderID, idempotencyKey string, holdSeconds, commissionPercent int) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := r.completeOrderFinanciallyTx(ctx, tx, orderID, idempotencyKey, holdSeconds, commissionPercent); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) completeOrderFinanciallyTx(ctx context.Context, tx *sql.Tx, orderID, idempotencyKey string, holdSeconds, commissionPercent int) error {
	var driverID sql.NullString
	var paymentMethod string
	var orderAmount sql.NullInt64
	var surchargeAmount int64
	err := tx.QueryRowContext(ctx, `
SELECT o.driver_id,
	COALESCE((SELECT payment_method FROM payments WHERE order_id = o.id ORDER BY created_at DESC LIMIT 1), o.payment_method, 'cash'),
	o.price_total,
	COALESCE(o.surcharge_amount, 0)
FROM orders o
WHERE o.id = $1
FOR UPDATE`, orderID).Scan(&driverID, &paymentMethod, &orderAmount, &surchargeAmount)
	if errors.Is(err, sql.ErrNoRows) {
		return paymentdomain.ErrPaymentNotFound
	}
	if err != nil {
		return err
	}

	// Idempotency guard. It is deliberately evaluated only AFTER the order row
	// has been locked FOR UPDATE above: two concurrent duplicates of the same
	// completion both take the lock, so whichever commits first here, the
	// second one re-checks the key on the just-committed snapshot, observes the
	// wallet_transaction and short-circuits. Checking the key before the lock
	// would let both callers see "not settled yet" and double-apply the debt
	// (or double-credit a card order) despite the ON CONFLICT insert guard.
	//
	// The check matches the base key OR any derived key (base + ":<suffix>"):
	// the cash branch records "<base>:cash_debt" and the card branch records
	// "<base>:debt_repayment"/"<base>:order_income", so a retry of the same
	// settlement must be recognised regardless of which wallet_transaction was
	// actually written.
	var exists bool
	err = tx.QueryRowContext(ctx, `
SELECT EXISTS(
	SELECT 1 FROM wallet_transactions
	WHERE idempotency_key = $1 OR idempotency_key LIKE $1 || ':%'
)`, idempotencyKey).Scan(&exists)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}

	if !driverID.Valid || driverID.String == "" {
		return errors.New("order has no driver")
	}
	if !orderAmount.Valid || orderAmount.Int64 <= 0 {
		return errors.New("order amount is missing")
	}

	var paymentID sql.NullString
	var paymentStatus sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT id, status FROM payments WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1`, orderID).Scan(&paymentID, &paymentStatus)
	if errors.Is(err, sql.ErrNoRows) {
		// No payment record — legitimate for cash orders, proceed.
	} else if err != nil {
		return fmt.Errorf("scan payment in CompleteOrderFinancially: %w", err)
	}
	if paymentMethod == string(paymentdomain.PaymentMethodCard) && paymentStatus.String != string(paymentdomain.PaymentStatusSucceeded) {
		return errors.New("card payment is not succeeded")
	}

	walletID, err := ensureWalletLocked(ctx, tx, driverID.String)
	if err != nil {
		return err
	}

	total := orderAmount.Int64
	base := total - surchargeAmount

	effectivePercent := commissionPercent
	active, err := r.hasActiveSubscriptionTx(ctx, tx, driverID.String)
	if err != nil {
		return fmt.Errorf("check driver subscription: %w", err)
	}
	if active {
		effectivePercent = 0
	}

	commission := (base*int64(effectivePercent) + 50) / 100
	driverAmount := total - commission

	if commission+driverAmount != total {
		return fmt.Errorf("split mismatch: total=%d commission=%d driver=%d", total, commission, driverAmount)
	}
	if commission < 0 || driverAmount < 0 {
		return fmt.Errorf("negative split: commission=%d driver=%d", commission, driverAmount)
	}

	now := time.Now().UTC()
	if paymentMethod == string(paymentdomain.PaymentMethodCash) {
		if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET debt_balance = debt_balance + $1, updated_at = NOW() WHERE id = $2`, commission, walletID); err != nil {
			return err
		}
		if err := insertWalletTx(ctx, tx, walletID, driverID.String, &orderID, nullableString(paymentID), nil, paymentdomain.WalletTypeCashCommissionDebt, paymentdomain.WalletDirectionCredit, commission, paymentdomain.WalletTxStatusSucceeded, "Tow Truck commission debt for cash order", idempotencyKey+":cash_debt", nil); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE orders SET financially_completed_at = NOW(), financial_status = 'completed', driver_amount = $2, commission_amount = $3 WHERE id = $1`, orderID, driverAmount, commission)
		if err != nil {
			return err
		}
		if _, releaseErr := tx.ExecContext(ctx, `UPDATE drivers SET status = 'online', current_order_id = NULL, updated_at = NOW() WHERE id = $1 AND current_order_id = $2`, driverID.String, orderID); releaseErr != nil {
			return releaseErr
		}
		return nil
	}

	var debt int64
	if err := tx.QueryRowContext(ctx, `SELECT debt_balance FROM driver_wallets WHERE id = $1 FOR UPDATE`, walletID).Scan(&debt); err != nil {
		return err
	}
	repayment := minInt64(driverAmount, debt)
	if repayment > 0 {
		if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET debt_balance = debt_balance - $1, updated_at = NOW() WHERE id = $2`, repayment, walletID); err != nil {
			return err
		}
		if err := insertWalletTx(ctx, tx, walletID, driverID.String, &orderID, nullableString(paymentID), nil, paymentdomain.WalletTypeDebtRepayment, paymentdomain.WalletDirectionDebit, repayment, paymentdomain.WalletTxStatusSucceeded, "Debt repayment from card order", idempotencyKey+":debt_repayment", nil); err != nil {
			return err
		}
	}
	pending := driverAmount - repayment
	if pending > 0 {
		availableAfter := now.Add(time.Duration(holdSeconds) * time.Second)
		if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET pending_balance = pending_balance + $1, updated_at = NOW() WHERE id = $2`, pending, walletID); err != nil {
			return err
		}
		if err := insertWalletTx(ctx, tx, walletID, driverID.String, &orderID, nullableString(paymentID), nil, paymentdomain.WalletTypeOrderIncome, paymentdomain.WalletDirectionCredit, pending, paymentdomain.WalletTxStatusPending, "Driver income for card order", idempotencyKey+":order_income", &availableAfter); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE orders SET financially_completed_at = NOW(), financial_status = 'completed', driver_amount = $2, commission_amount = $3 WHERE id = $1`, orderID, driverAmount, commission); err != nil {
		return err
	}
	if _, releaseErr := tx.ExecContext(ctx, `UPDATE drivers SET status = 'online', current_order_id = NULL, updated_at = NOW() WHERE id = $1 AND current_order_id = $2`, driverID.String, orderID); releaseErr != nil {
		return releaseErr
	}
	return nil
}

func (r *PaymentRepository) hasActiveSubscriptionTx(ctx context.Context, tx *sql.Tx, driverID string) (bool, error) {
	var exists bool
	err := tx.QueryRowContext(ctx, `
SELECT EXISTS(
	SELECT 1 FROM subscriptions
	WHERE driver_id = $1 AND status = 'active' AND ends_at > NOW()
)`, driverID).Scan(&exists)
	return exists, err
}

func (r *PaymentRepository) ReleasePendingBalances(ctx context.Context, limit int) (int, error) {
	transactions, err := r.ListReleasablePendingTransactions(ctx, limit)
	if err != nil {
		return 0, err
	}
	count := 0
	for _, transaction := range transactions {
		if err := r.MarkTransactionReleased(ctx, transaction.ID); err != nil {
			return count, err
		}
		count++
	}
	return count, nil
}

func (r *PaymentRepository) ListReleasablePendingTransactions(ctx context.Context, limit int) ([]paymentdomain.WalletTransaction, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT id, wallet_id, driver_id, order_id, payment_id, payout_id, type, direction, amount, currency, status, description, idempotency_key, available_after, created_at
FROM wallet_transactions
WHERE type = 'order_income' AND status = 'pending' AND available_after <= NOW()
ORDER BY created_at ASC
LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var txs []paymentdomain.WalletTransaction
	for rows.Next() {
		tx, err := scanWalletTxRows(rows)
		if err != nil {
			return nil, err
		}
		txs = append(txs, tx)
	}
	return txs, rows.Err()
}

func (r *PaymentRepository) MarkTransactionReleased(ctx context.Context, txID string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var item struct {
		id, walletID, driverID string
		amount                 int64
		orderID, paymentID     sql.NullString
	}
	err = tx.QueryRowContext(ctx, `
SELECT id, wallet_id, driver_id, amount, order_id, payment_id
FROM wallet_transactions
WHERE id = $1 AND type = 'order_income' AND status = 'pending' AND available_after <= NOW()
FOR UPDATE`, txID).Scan(&item.id, &item.walletID, &item.driverID, &item.amount, &item.orderID, &item.paymentID)
	if errors.Is(err, sql.ErrNoRows) {
		return tx.Commit()
	}
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `SELECT id FROM driver_wallets WHERE id = $1 FOR UPDATE`, item.walletID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
UPDATE driver_wallets
SET pending_balance = pending_balance - $1, available_balance = available_balance + $1, updated_at = NOW()
WHERE id = $2`, item.amount, item.walletID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE wallet_transactions SET status = 'available' WHERE id = $1`, item.id); err != nil {
		return err
	}
	orderID := nullableString(item.orderID)
	paymentID := nullableString(item.paymentID)
	if err := insertWalletTx(ctx, tx, item.walletID, item.driverID, orderID, paymentID, nil, paymentdomain.WalletTypePendingToAvailable, paymentdomain.WalletDirectionCredit, item.amount, paymentdomain.WalletTxStatusSucceeded, "Released pending income to available balance", "release:"+item.id, nil); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) GetDriverWallet(ctx context.Context, driverID string) (*paymentdomain.DriverWallet, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	walletID, err := ensureWalletLocked(ctx, tx, driverID)
	if err != nil {
		return nil, err
	}
	w, err := scanWallet(tx.QueryRowContext(ctx, walletSelectSQL()+` WHERE id = $1`, walletID))
	if err != nil {
		return nil, err
	}
	return w, tx.Commit()
}

// GetDriverEarnings aggregates the driver's completed-order income for the
// today/week/month periods in a single pass over the orders table (period
// boundaries are supplied by the caller as absolute timestamps) and reads the
// driver's rating from the drivers table. Amounts are in kopecks.
func (r *PaymentRepository) GetDriverEarnings(ctx context.Context, driverID string, todayStart, weekStart, monthStart time.Time) (paymentdomain.DriverEarnings, error) {
	var e paymentdomain.DriverEarnings
	err := r.db.QueryRowContext(ctx, `
SELECT
  COALESCE(SUM(driver_amount) FILTER (WHERE financially_completed_at >= $2), 0),
  COUNT(*)                    FILTER (WHERE financially_completed_at >= $2),
  COALESCE(SUM(driver_amount) FILTER (WHERE financially_completed_at >= $3), 0),
  COUNT(*)                    FILTER (WHERE financially_completed_at >= $3),
  COALESCE(SUM(driver_amount) FILTER (WHERE financially_completed_at >= $4), 0),
  COUNT(*)                    FILTER (WHERE financially_completed_at >= $4)
FROM orders
WHERE driver_id = $1 AND status = 'completed'`,
		driverID, todayStart, weekStart, monthStart,
	).Scan(
		&e.TodayAmount, &e.TodayOrders,
		&e.WeekAmount, &e.WeekOrders,
		&e.MonthAmount, &e.MonthOrders,
	)
	if err != nil {
		return paymentdomain.DriverEarnings{}, err
	}

	err = r.db.QueryRowContext(ctx,
		`SELECT COALESCE(rating_average, 0), COALESCE(rating_count, 0) FROM drivers WHERE id = $1`,
		driverID,
	).Scan(&e.RatingAverage, &e.RatingCount)
	if errors.Is(err, sql.ErrNoRows) {
		return e, nil
	}
	if err != nil {
		return paymentdomain.DriverEarnings{}, err
	}
	return e, nil
}

func (r *PaymentRepository) ListWalletTransactions(ctx context.Context, driverID string, limit int) ([]paymentdomain.WalletTransaction, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, wallet_id, driver_id, order_id, payment_id, payout_id, type, direction, amount, currency, status, description, idempotency_key, available_after, created_at
FROM wallet_transactions
WHERE driver_id = $1
AND type <> 'pending_to_available'
ORDER BY created_at DESC
LIMIT $2`, driverID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var txs []paymentdomain.WalletTransaction
	for rows.Next() {
		tx, err := scanWalletTxRows(rows)
		if err != nil {
			return nil, err
		}
		txs = append(txs, tx)
	}
	return txs, rows.Err()
}

// ListDebtTransactions returns the driver's cash-commission debt history —
// everything that built the debt (cash_commission_debt) and everything that
// reduced it (debt_repayment) — newest first, joined to the linked order total.
func (r *PaymentRepository) ListDebtTransactions(ctx context.Context, driverID string, limit int) ([]paymentdomain.DriverDebtTransaction, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 500 {
		limit = 500
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT wt.id, wt.order_id, wt.type, wt.direction, wt.amount, wt.currency, wt.status, wt.description, COALESCE(o.price_total, 0), wt.created_at
FROM wallet_transactions wt
LEFT JOIN orders o ON o.id = wt.order_id
WHERE wt.driver_id = $1
AND wt.type IN ('cash_commission_debt', 'debt_repayment')
ORDER BY wt.created_at DESC
LIMIT $2`, driverID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []paymentdomain.DriverDebtTransaction
	for rows.Next() {
		var item paymentdomain.DriverDebtTransaction
		var typ, direction, status string
		var orderID sql.NullString
		if err := rows.Scan(
			&item.ID,
			&orderID,
			&typ,
			&direction,
			&item.Amount,
			&item.Currency,
			&status,
			&item.Description,
			&item.OrderAmount,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		item.OrderID = nullableString(orderID)
		item.Type = paymentdomain.WalletTransactionType(typ)
		item.Direction = paymentdomain.WalletDirection(direction)
		item.Status = paymentdomain.WalletTransactionStatus(status)
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *PaymentRepository) ListPayouts(ctx context.Context, driverID string, limit int) ([]paymentdomain.Payout, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts WHERE driver_id = $1 ORDER BY created_at DESC LIMIT $2`, driverID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var payouts []paymentdomain.Payout
	for rows.Next() {
		p, err := scanPayoutRows(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}

func (r *PaymentRepository) ListPayoutMethods(ctx context.Context, driverID string) ([]paymentdomain.DriverPayoutMethod, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, driver_id, provider_recipient_id, type, masked_value, is_default, status, created_at
FROM driver_payout_methods WHERE driver_id = $1 ORDER BY is_default DESC, created_at DESC`, driverID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var methods []paymentdomain.DriverPayoutMethod
	for rows.Next() {
		var m paymentdomain.DriverPayoutMethod
		var typ string
		if err := rows.Scan(&m.ID, &m.DriverID, &m.ProviderRecipientID, &typ, &m.MaskedValue, &m.IsDefault, &m.Status, &m.CreatedAt); err != nil {
			return nil, err
		}
		m.Type = paymentdomain.PayoutMethodType(typ)
		methods = append(methods, m)
	}
	return methods, rows.Err()
}

func (r *PaymentRepository) AddPayoutMethod(ctx context.Context, method paymentdomain.DriverPayoutMethod) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var count int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM driver_payout_methods WHERE driver_id = $1`, method.DriverID).Scan(&count); err != nil {
		return err
	}
	isDefault := method.IsDefault || count == 0
	if isDefault {
		if _, err := tx.ExecContext(ctx, `UPDATE driver_payout_methods SET is_default = FALSE WHERE driver_id = $1`, method.DriverID); err != nil {
			return err
		}
	}
	_, err = tx.ExecContext(ctx, `
INSERT INTO driver_payout_methods (id, driver_id, provider_recipient_id, type, masked_value, is_default, status, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (id) DO NOTHING`, method.ID, method.DriverID, method.ProviderRecipientID, string(method.Type), method.MaskedValue, isDefault, method.Status, method.CreatedAt)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) CreatePayout(ctx context.Context, payout *paymentdomain.Payout, idempotencyKey string) (*paymentdomain.Payout, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if idempotencyKey != "" {
		existing, err := scanPayout(tx.QueryRowContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts WHERE idempotency_key = $1`, idempotencyKey))
		if err == nil {
			return existing, tx.Commit()
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
	}
	walletID, err := ensureWalletLocked(ctx, tx, payout.DriverID)
	if err != nil {
		return nil, err
	}
	var available int64
	if err := tx.QueryRowContext(ctx, `SELECT available_balance FROM driver_wallets WHERE id = $1 FOR UPDATE`, walletID).Scan(&available); err != nil {
		return nil, err
	}
	// Balance is debited only at pay-out time (ApprovePayout/MarkPayoutPaid),
	// so treat amounts of already open payout requests as committed funds to
	// prevent concurrent requests from collectively exceeding the balance.
	var outstandingSum int64
	if err := tx.QueryRowContext(ctx, `
SELECT COALESCE(SUM(amount), 0) FROM payouts
WHERE driver_id = $1 AND status IN ('created', 'processing', 'manual_review')`, payout.DriverID).Scan(&outstandingSum); err != nil {
		return nil, err
	}
	if payout.Amount <= 0 {
		return nil, paymentdomain.ErrInvalidAmount
	}
	effectiveAvailable := available - outstandingSum
	if payout.Amount > effectiveAvailable {
		return nil, paymentdomain.ErrInsufficientFunds
	}
	payout.WalletID = walletID
	created, err := scanPayout(tx.QueryRowContext(ctx, `
INSERT INTO payouts (id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
ON CONFLICT (idempotency_key) WHERE idempotency_key <> '' DO UPDATE SET updated_at = payouts.updated_at
RETURNING id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at`,
		payout.ID, payout.DriverID, payout.WalletID, string(payout.Provider), payout.ProviderPayoutID, payout.Amount, payout.Currency, string(payout.Status), payout.FailureReason, idempotencyKey, payout.PaidAt, payout.CreatedAt, payout.UpdatedAt))
	if err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO wallet_transaction_locks (idempotency_key, created_at) VALUES ($1, NOW()) ON CONFLICT DO NOTHING`, idempotencyKey); err != nil {
		return nil, err
	}
	return created, tx.Commit()
}

func (r *PaymentRepository) MarkPayoutPaid(ctx context.Context, payoutID, providerPayoutID, idempotencyKey string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var payout paymentdomain.Payout
	var provider, status string
	err = tx.QueryRowContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts WHERE id = $1 FOR UPDATE`, payoutID).Scan(&payout.ID, &payout.DriverID, &payout.WalletID, &provider, &payout.ProviderPayoutID, &payout.Amount, &payout.Currency, &status, &payout.FailureReason, &payout.IdempotencyKey, &payout.PaidAt, &payout.CreatedAt, &payout.UpdatedAt)
	if err != nil {
		return err
	}
	if status == string(paymentdomain.PayoutStatusPaid) {
		return tx.Commit()
	}
	if _, err := tx.ExecContext(ctx, `SELECT id FROM driver_wallets WHERE id = $1 FOR UPDATE`, payout.WalletID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET available_balance = available_balance - $1, updated_at = NOW() WHERE id = $2`, payout.Amount, payout.WalletID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payouts SET status = 'paid', provider_payout_id = $2, paid_at = NOW(), updated_at = NOW() WHERE id = $1`, payoutID, providerPayoutID); err != nil {
		return err
	}
	if err := insertWalletTx(ctx, tx, payout.WalletID, payout.DriverID, nil, nil, &payout.ID, paymentdomain.WalletTypePayout, paymentdomain.WalletDirectionDebit, payout.Amount, paymentdomain.WalletTxStatusSucceeded, "Driver payout", idempotencyKey, nil); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) MarkPayoutFailed(ctx context.Context, payoutID, reason string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE payouts SET status = 'failed', failure_reason = $2, updated_at = NOW() WHERE id = $1`, payoutID, reason)
	return err
}

func (r *PaymentRepository) ListStuckPayouts(ctx context.Context, olderThan time.Duration) ([]paymentdomain.Payout, error) {
	threshold := time.Now().Add(-olderThan)
	rows, err := r.db.QueryContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts
WHERE status = 'created'
  AND created_at < $1
ORDER BY created_at ASC`, threshold)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var payouts []paymentdomain.Payout
	for rows.Next() {
		p, err := scanPayoutRows(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}

// GetPayout fetches a single payout by ID. Returns ErrPayoutNotFound on missing.
func (r *PaymentRepository) GetPayout(ctx context.Context, payoutID string) (*paymentdomain.Payout, error) {
	const query = `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts WHERE id = $1`
	payout, err := scanPayout(r.db.QueryRowContext(ctx, query, payoutID))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, paymentdomain.ErrPayoutNotFound
		}
		return nil, err
	}
	return payout, nil
}

// ApprovePayout marks a payout as paid (admin approval workflow) and debits
// the driver's available balance, mirroring MarkPayoutPaid but allowed only
// for payouts in approvable statuses: created, processing or manual_review.
// providerPayoutID may be empty when admin approves a payout that has no
// matching provider record (manual SBP/bank transfer).
func (r *PaymentRepository) ApprovePayout(ctx context.Context, payoutID, moderatorID, providerPayoutID string, now time.Time) (*paymentdomain.Payout, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	payout, err := scanPayout(tx.QueryRowContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts WHERE id = $1 FOR UPDATE`, payoutID))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, paymentdomain.ErrPayoutNotFound
		}
		return nil, err
	}

	if payout.Status == paymentdomain.PayoutStatusPaid {
		// Idempotent: already approved.
		return payout, tx.Commit()
	}
	if !payoutIsApprovable(payout.Status) {
		return nil, paymentdomain.ErrPayoutNotApprovable
	}

	if _, err := tx.ExecContext(ctx, `SELECT id FROM driver_wallets WHERE id = $1 FOR UPDATE`, payout.WalletID); err != nil {
		return nil, err
	}
	var balance int64
	if err := tx.QueryRowContext(ctx, `SELECT available_balance FROM driver_wallets WHERE id = $1`, payout.WalletID).Scan(&balance); err != nil {
		return nil, err
	}
	if balance < payout.Amount {
		return nil, paymentdomain.ErrInsufficientFunds
	}
	if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET available_balance = available_balance - $1, updated_at = $2 WHERE id = $3`, payout.Amount, now, payout.WalletID); err != nil {
		return nil, err
	}

	var providerArg any
	if providerPayoutID != "" {
		providerArg = providerPayoutID
	} else {
		providerArg = nil
	}
	updated, err := scanPayout(tx.QueryRowContext(ctx, `
UPDATE payouts
SET status = 'paid',
	provider_payout_id = COALESCE($2, provider_payout_id),
	paid_at = $3,
	updated_at = $3
WHERE id = $1
RETURNING id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at`,
		payoutID, providerArg, now))
	if err != nil {
		return nil, err
	}

	idempotency := fmt.Sprintf("admin_approve_payout:%s", payoutID)
	if err := insertWalletTx(
		ctx, tx, payout.WalletID, payout.DriverID,
		nil, nil, &payout.ID,
		paymentdomain.WalletTypePayout, paymentdomain.WalletDirectionDebit,
		payout.Amount, paymentdomain.WalletTxStatusSucceeded,
		"Admin approved driver payout", idempotency, nil,
	); err != nil {
		return nil, err
	}

	if _, err := tx.ExecContext(ctx, `
INSERT INTO moderation_audit_log (id, entity_type, entity_id, action, reason, moderator_id, created_at)
VALUES ($1, 'payout', $2, 'approve', $3, $4, $5)
ON CONFLICT (id) DO NOTHING`,
		"mod_payout_approve_"+payoutID, payoutID, "admin approval", moderatorID, now); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return updated, nil
}

// RejectPayout cancels a payout that has not been paid yet, records the
// reason, writes an audit log entry and credits the reserved amount back to
// the driver's available balance via a corrective wallet transaction so the
// driver does not lose funds that were tentatively reserved by CreatePayout.
//
// Only payouts in created / processing / manual_review can be rejected.
// Already-paid or already-failed/cancelled payouts return ErrPayoutNotRejectable.
func (r *PaymentRepository) RejectPayout(ctx context.Context, payoutID, moderatorID, reason string, now time.Time) (*paymentdomain.Payout, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	payout, err := scanPayout(tx.QueryRowContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
FROM payouts WHERE id = $1 FOR UPDATE`, payoutID))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, paymentdomain.ErrPayoutNotFound
		}
		return nil, err
	}
	if !payoutIsRejectable(payout.Status) {
		return nil, paymentdomain.ErrPayoutNotRejectable
	}

	updated, err := scanPayout(tx.QueryRowContext(ctx, `
UPDATE payouts
SET status = 'cancelled',
	failure_reason = $2,
	updated_at = $3
WHERE id = $1
RETURNING id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at`,
		payoutID, reason, now))
	if err != nil {
		return nil, err
	}

	// CreatePayout reserves money on the driver wallet by virtue of checking
	// available_balance >= amount but it does not yet move funds; the
	// available_balance is debited only on MarkPayoutPaid/ApprovePayout.
	// Therefore on rejection we do not need to re-credit the wallet, but we
	// record a zero-amount audit transaction so admins see the rejection in
	// the wallet history.
	idempotency := fmt.Sprintf("admin_reject_payout:%s", payoutID)
	if err := insertWalletTx(
		ctx, tx, payout.WalletID, payout.DriverID,
		nil, nil, &payout.ID,
		paymentdomain.WalletTypeAdjustment, paymentdomain.WalletDirectionCredit,
		0, paymentdomain.WalletTxStatusSucceeded,
		"Admin rejected payout: "+reason, idempotency, nil,
	); err != nil {
		return nil, err
	}

	if _, err := tx.ExecContext(ctx, `
INSERT INTO moderation_audit_log (id, entity_type, entity_id, action, reason, moderator_id, created_at)
VALUES ($1, 'payout', $2, 'reject', $3, $4, $5)
ON CONFLICT (id) DO NOTHING`,
		"mod_payout_reject_"+payoutID, payoutID, reason, moderatorID, now); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return updated, nil
}

func payoutIsApprovable(status paymentdomain.PayoutStatus) bool {
	switch status {
	case paymentdomain.PayoutStatusCreated,
		paymentdomain.PayoutStatusProcessing,
		paymentdomain.PayoutStatusManualReview:
		return true
	default:
		return false
	}
}

func payoutIsRejectable(status paymentdomain.PayoutStatus) bool {
	switch status {
	case paymentdomain.PayoutStatusCreated,
		paymentdomain.PayoutStatusProcessing,
		paymentdomain.PayoutStatusManualReview:
		return true
	default:
		return false
	}
}

// ListAdminRefunds returns refunds with filters for the admin panel.
// Filters by status, payment_id, order_id (resolved through payments) and
// a created_at date range. Returns total count for pagination.
func (r *PaymentRepository) ListAdminRefunds(ctx context.Context, filter paymentdomain.AdminRefundFilter) ([]paymentdomain.Refund, int64, error) {
	limit := filter.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	offset := filter.Offset
	if offset < 0 {
		offset = 0
	}

	conds := []string{}
	args := []any{}
	add := func(cond string, value any) {
		args = append(args, value)
		conds = append(conds, strings.ReplaceAll(cond, "?", argRef(len(args))))
	}
	if s := strings.TrimSpace(filter.Status); s != "" {
		add("r.status = ?", s)
	}
	if s := strings.TrimSpace(filter.PaymentID); s != "" {
		add("r.payment_id = ?", s)
	}
	if s := strings.TrimSpace(filter.OrderID); s != "" {
		add("EXISTS (SELECT 1 FROM payments p WHERE p.id = r.payment_id AND p.order_id = ?)", s)
	}
	if filter.From != nil {
		add("r.created_at >= ?", *filter.From)
	}
	if filter.To != nil {
		add("r.created_at <= ?", *filter.To)
	}
	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	var total int64
	if err := r.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM refunds r "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listSQL := `
SELECT id, payment_id, provider_refund_id, amount, currency, reason, status, idempotency_key, created_at, updated_at
FROM refunds r
` + where + `
ORDER BY r.created_at DESC
LIMIT ` + argRef(len(args)+1) + ` OFFSET ` + argRef(len(args)+2)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, listSQL, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := make([]paymentdomain.Refund, 0, limit)
	for rows.Next() {
		refund, err := scanRefund(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *refund)
	}
	return out, total, rows.Err()
}

// ListWalletTransactionsByOrder returns all wallet transactions linked to a
// single order, ordered chronologically. Amounts in kopecks.
func (r *PaymentRepository) ListWalletTransactionsByOrder(ctx context.Context, orderID string) ([]paymentdomain.WalletTransaction, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, wallet_id, driver_id, order_id, payment_id, payout_id, type, direction, amount, currency, status, description, idempotency_key, available_after, created_at
FROM wallet_transactions
WHERE order_id = $1
ORDER BY created_at ASC`, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var txs []paymentdomain.WalletTransaction
	for rows.Next() {
		tx, err := scanWalletTxRows(rows)
		if err != nil {
			return nil, err
		}
		txs = append(txs, tx)
	}
	return txs, rows.Err()
}

func (r *PaymentRepository) GetActiveDriverSubscription(ctx context.Context, driverID string) (*paymentdomain.Subscription, error) {
	subscription, err := scanSubscription(r.db.QueryRowContext(ctx, subscriptionSelectSQL()+`
WHERE driver_id = $1 AND status = 'active' AND ends_at > NOW()
ORDER BY ends_at DESC
LIMIT 1`, driverID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return subscription, err
}

func (r *PaymentRepository) GetLatestDriverSubscription(ctx context.Context, driverID string) (*paymentdomain.Subscription, error) {
	subscription, err := scanSubscription(r.db.QueryRowContext(ctx, subscriptionSelectSQL()+`
WHERE driver_id = $1
ORDER BY COALESCE(ends_at, created_at) DESC
LIMIT 1`, driverID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return subscription, err
}

func (r *PaymentRepository) ActivateSubscriptionByPayment(ctx context.Context, paymentID string) error {
	_, err := r.db.ExecContext(ctx, `
UPDATE subscriptions
SET status = 'active', starts_at = COALESCE(starts_at, NOW()), ends_at = COALESCE(ends_at, NOW() + INTERVAL '30 days'), updated_at = NOW()
WHERE payment_id = $1`, paymentID)
	return err
}

func (r *PaymentRepository) ExportFinanceReport(ctx context.Context, reportType string) ([][]string, error) {
	reportType = strings.ReplaceAll(reportType, "-", "_")
	if reportType == "transactions" {
		reportType = "wallet_transactions"
	}
	queries := map[string]string{
		"orders":              `SELECT id, user_id, COALESCE(driver_id,'') AS driver_id, status, (price_total::NUMERIC / 100)::TEXT AS price_total_rub, payment_method, created_at::TEXT AS created_at FROM orders ORDER BY created_at DESC`,
		"payments":            `SELECT id, COALESCE(order_id,'') AS order_id, user_id, provider, COALESCE(provider_payment_id,'') AS provider_payment_id, payment_method, purpose, (amount::NUMERIC / 100)::TEXT AS amount_rub, currency, status, created_at::TEXT AS created_at FROM payments ORDER BY created_at DESC`,
		"payouts":             `SELECT id, driver_id, (amount::NUMERIC / 100)::TEXT AS amount_rub, currency, status, COALESCE(provider_payout_id,'') AS provider_payout_id, created_at::TEXT AS created_at FROM payouts ORDER BY created_at DESC`,
		"wallets":             `SELECT id, driver_id, (available_balance::NUMERIC / 100)::TEXT AS available_balance_rub, (pending_balance::NUMERIC / 100)::TEXT AS pending_balance_rub, (debt_balance::NUMERIC / 100)::TEXT AS debt_balance_rub, currency, updated_at::TEXT AS updated_at FROM driver_wallets ORDER BY updated_at DESC`,
		"commissions":         `SELECT id, driver_id, COALESCE(order_id,'') AS order_id, type, (amount::NUMERIC / 100)::TEXT AS amount_rub, currency, created_at::TEXT AS created_at FROM wallet_transactions WHERE type IN ('commission','cash_commission_debt','debt_repayment') ORDER BY created_at DESC`,
		"subscriptions":       `SELECT id, driver_id, plan_id, payment_id, (amount::NUMERIC / 100)::TEXT AS amount_rub, currency, status, created_at::TEXT AS created_at FROM subscriptions ORDER BY created_at DESC`,
		"cash_debts":          `SELECT id, driver_id, COALESCE(order_id,'') AS order_id, (amount::NUMERIC / 100)::TEXT AS amount_rub, status, created_at::TEXT AS created_at FROM wallet_transactions WHERE type = 'cash_commission_debt' ORDER BY created_at DESC`,
		"wallet_transactions": `SELECT id, wallet_id, driver_id, COALESCE(order_id,'') AS order_id, COALESCE(payment_id,'') AS payment_id, COALESCE(payout_id,'') AS payout_id, type, direction, (amount::NUMERIC / 100)::TEXT AS amount_rub, currency, status, description, created_at::TEXT AS created_at FROM wallet_transactions ORDER BY created_at DESC`,
	}
	query, ok := queries[reportType]
	if !ok {
		return nil, errors.New("unknown report type")
	}
	rows, err := r.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	out := [][]string{cols}
	for rows.Next() {
		values := make([]sql.NullString, len(cols))
		ptrs := make([]any, len(cols))
		for i := range values {
			ptrs[i] = &values[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			return nil, err
		}
		line := make([]string, len(cols))
		for i, v := range values {
			if v.Valid {
				line[i] = v.String
			}
		}
		out = append(out, line)
	}
	return out, rows.Err()
}

func paymentSelectSQL() string {
	return `SELECT id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at FROM payments`
}

func walletSelectSQL() string {
	return `SELECT id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at FROM driver_wallets`
}

func subscriptionSelectSQL() string {
	return `SELECT id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at FROM subscriptions `
}

func scanPayment(row interface{ Scan(dest ...any) error }) (*paymentdomain.Payment, error) {
	var p paymentdomain.Payment
	var provider, method, purpose, status string
	var orderID, driverID, providerPaymentID, confirmationURL sql.NullString
	if err := row.Scan(&p.ID, &orderID, &driverID, &p.UserID, &provider, &providerPaymentID, &method, &purpose, &p.Amount, &p.Currency, &status, &confirmationURL, &p.IdempotencyKey, &p.PaidAt, &p.CreatedAt, &p.UpdatedAt); err != nil {
		return nil, err
	}
	p.Provider = paymentdomain.PaymentProvider(provider)
	p.PaymentMethod = paymentdomain.PaymentMethodType(method)
	p.Purpose = paymentdomain.PaymentPurpose(purpose)
	p.Status = paymentdomain.PaymentStatus(status)
	p.OrderID = nullableString(orderID)
	p.DriverID = nullableString(driverID)
	p.ProviderPaymentID = nullableString(providerPaymentID)
	p.ConfirmationURL = nullableString(confirmationURL)
	return &p, nil
}

func scanWallet(row interface{ Scan(dest ...any) error }) (*paymentdomain.DriverWallet, error) {
	var w paymentdomain.DriverWallet
	if err := row.Scan(&w.ID, &w.DriverID, &w.AvailableBalance, &w.PendingBalance, &w.DebtBalance, &w.Currency, &w.CreatedAt, &w.UpdatedAt); err != nil {
		return nil, err
	}
	return &w, nil
}

func scanSubscription(row interface{ Scan(dest ...any) error }) (*paymentdomain.Subscription, error) {
	var s paymentdomain.Subscription
	var status string
	if err := row.Scan(&s.ID, &s.DriverID, &s.PlanID, &s.PaymentID, &s.Amount, &s.Currency, &status, &s.StartsAt, &s.EndsAt, &s.CreatedAt, &s.UpdatedAt); err != nil {
		return nil, err
	}
	s.Plan = s.PlanID
	s.LastPaymentID = s.PaymentID
	s.PeriodStart = s.StartsAt
	s.PeriodEnd = s.EndsAt
	s.Status = paymentdomain.SubscriptionStatus(status)
	return &s, nil
}

func scanPayout(row interface{ Scan(dest ...any) error }) (*paymentdomain.Payout, error) {
	var p paymentdomain.Payout
	var provider, status string
	if err := row.Scan(&p.ID, &p.DriverID, &p.WalletID, &provider, &p.ProviderPayoutID, &p.Amount, &p.Currency, &status, &p.FailureReason, &p.IdempotencyKey, &p.PaidAt, &p.CreatedAt, &p.UpdatedAt); err != nil {
		return nil, err
	}
	p.Provider = paymentdomain.PaymentProvider(provider)
	p.Status = paymentdomain.PayoutStatus(status)
	return &p, nil
}

func scanPayoutRows(rows *sql.Rows) (paymentdomain.Payout, error) {
	p, err := scanPayout(rows)
	if err != nil {
		return paymentdomain.Payout{}, err
	}
	return *p, nil
}

func scanWalletTxRows(rows *sql.Rows) (paymentdomain.WalletTransaction, error) {
	var t paymentdomain.WalletTransaction
	var typ, direction, status string
	var orderID, paymentID, payoutID sql.NullString
	if err := rows.Scan(&t.ID, &t.WalletID, &t.DriverID, &orderID, &paymentID, &payoutID, &typ, &direction, &t.Amount, &t.Currency, &status, &t.Description, &t.IdempotencyKey, &t.AvailableAfter, &t.CreatedAt); err != nil {
		return paymentdomain.WalletTransaction{}, err
	}
	t.OrderID = nullableString(orderID)
	t.PaymentID = nullableString(paymentID)
	t.PayoutID = nullableString(payoutID)
	t.Type = paymentdomain.WalletTransactionType(typ)
	t.Direction = paymentdomain.WalletDirection(direction)
	t.Status = paymentdomain.WalletTransactionStatus(status)
	return t, nil
}

func scanRefund(row interface{ Scan(dest ...any) error }) (*paymentdomain.Refund, error) {
	var refund paymentdomain.Refund
	var status string
	if err := row.Scan(&refund.ID, &refund.PaymentID, &refund.ProviderRefundID, &refund.Amount, &refund.Currency, &refund.Reason, &status, &refund.IdempotencyKey, &refund.CreatedAt, &refund.UpdatedAt); err != nil {
		return nil, err
	}
	refund.Status = paymentdomain.RefundStatus(status)
	return &refund, nil
}

func ensureWalletLocked(ctx context.Context, tx *sql.Tx, driverID string) (string, error) {
	var walletID string
	err := tx.QueryRowContext(ctx, `SELECT id FROM driver_wallets WHERE driver_id = $1 FOR UPDATE`, driverID).Scan(&walletID)
	if errors.Is(err, sql.ErrNoRows) {
		err = tx.QueryRowContext(ctx, `
INSERT INTO driver_wallets (id, driver_id, available_balance, pending_balance, debt_balance, currency, created_at, updated_at)
VALUES ($1, $2, 0, 0, 0, 'RUB', NOW(), NOW())
ON CONFLICT (driver_id) DO UPDATE SET updated_at = driver_wallets.updated_at
RETURNING id`, "wallet_"+driverID, driverID).Scan(&walletID)
		if err != nil {
			return "", err
		}
		return walletID, nil
	}
	return walletID, err
}

func insertWalletTx(ctx context.Context, tx *sql.Tx, walletID, driverID string, orderID, paymentID, payoutID *string, typ paymentdomain.WalletTransactionType, direction paymentdomain.WalletDirection, amount int64, status paymentdomain.WalletTransactionStatus, description, idempotencyKey string, availableAfter *time.Time) error {
	_, err := tx.ExecContext(ctx, `
INSERT INTO wallet_transactions (id, wallet_id, driver_id, order_id, payment_id, payout_id, type, direction, amount, currency, status, description, idempotency_key, available_after, created_at)
VALUES (gen_random_uuid()::TEXT, $1, $2, $3, $4, $5, $6, $7, $8, 'RUB', $9, $10, $11, $12, NOW())
ON CONFLICT (idempotency_key) DO NOTHING`,
		walletID, driverID, orderID, paymentID, payoutID, string(typ), string(direction), amount, string(status), description, idempotencyKey, availableAfter)
	return err
}

// --- WebhookTx implementation ---

type webhookTxImpl struct {
	tx   *sql.Tx
	repo *PaymentRepository
}

func (w *webhookTxImpl) CheckProcessed(ctx context.Context, eventID, provider, eventType string, payload []byte) (bool, error) {
	var processed bool
	err := w.tx.QueryRowContext(ctx, `
INSERT INTO payment_webhooks (id, provider, event_type, payload, processed, created_at)
VALUES ($1, $2, $3, $4, FALSE, NOW())
ON CONFLICT (id) DO UPDATE SET id = payment_webhooks.id
RETURNING processed`, eventID, provider, eventType, string(payload)).Scan(&processed)
	if err != nil {
		return false, err
	}
	return processed, nil
}

func (w *webhookTxImpl) UpdatePaymentFromProvider(ctx context.Context, providerPaymentID, status string, paid bool) (*paymentdomain.Payment, error) {
	var paidAt any
	if paid {
		paidAt = time.Now().UTC()
	}
	p, err := scanPayment(w.tx.QueryRowContext(ctx, `
UPDATE payments
SET status = $2, paid_at = COALESCE($3, paid_at), updated_at = NOW()
WHERE provider_payment_id = $1
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	amount, currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
		providerPaymentID, status, paidAt))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentNotFound
	}
	return p, err
}

func (w *webhookTxImpl) ActivateSubscriptionByPayment(ctx context.Context, paymentID string) error {
	_, err := w.tx.ExecContext(ctx, `
UPDATE subscriptions
SET status = 'active', starts_at = COALESCE(starts_at, NOW()), ends_at = COALESCE(ends_at, NOW() + INTERVAL '30 days'), updated_at = NOW()
WHERE payment_id = $1`, paymentID)
	return err
}

func (w *webhookTxImpl) ActivatePaymentMethodFromProvider(ctx context.Context, providerPaymentID, providerPaymentMethodID, brand, last4 string, expMonth, expYear int, holder string) error {
	return w.repo.activatePaymentMethodFromProviderTx(ctx, w.tx, providerPaymentID, providerPaymentMethodID, brand, last4, expMonth, expYear, holder)
}

func (w *webhookTxImpl) CompleteOrderFinancially(ctx context.Context, orderID, idempotencyKey string, holdSeconds, commissionPercent int) error {
	return w.repo.completeOrderFinanciallyTx(ctx, w.tx, orderID, idempotencyKey, holdSeconds, commissionPercent)
}

func (w *webhookTxImpl) UpdateOrderStatus(ctx context.Context, orderID, status string, updatedAt time.Time) error {
	_, err := w.tx.ExecContext(ctx, `UPDATE orders SET status = $2, updated_at = $3 WHERE id = $1`, orderID, status, updatedAt)
	return err
}

func (w *webhookTxImpl) MarkProcessed(ctx context.Context, eventID string) error {
	_, err := w.tx.ExecContext(ctx, `UPDATE payment_webhooks SET processed = TRUE, processed_at = NOW() WHERE id = $1`, eventID)
	return err
}

func (r *PaymentRepository) WithWebhookTx(ctx context.Context, fn func(paymentdomain.WebhookTx) error) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := fn(&webhookTxImpl{tx: tx, repo: r}); err != nil {
		return err
	}
	return tx.Commit()
}

func normalizeProviderBrand(value string) paymentdomain.CardBrand {
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch normalized {
	case "visa":
		return paymentdomain.CardBrandVisa
	case "mastercard", "master card":
		return paymentdomain.CardBrandMastercard
	case "mir", "мир":
		return paymentdomain.CardBrandMir
	default:
		return paymentdomain.CardBrandUnknown
	}
}

func nullableString(value sql.NullString) *string {
	if !value.Valid || value.String == "" {
		return nil
	}
	v := value.String
	return &v
}

func minInt64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}

func placeholders(count int) string {
	parts := make([]string, count)
	for i := range parts {
		parts[i] = fmt.Sprintf("$%d", i+1)
	}
	return strings.Join(parts, ",")
}
