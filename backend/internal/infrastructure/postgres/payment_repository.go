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

type PaymentRepository struct {
	db *sql.DB
}

func NewPaymentRepository(db *sql.DB) *PaymentRepository {
	return &PaymentRepository{db: db}
}

func (r *PaymentRepository) ListMethods(ctx context.Context, userID string) ([]paymentdomain.PaymentMethod, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, user_id, brand, last4, exp_month, exp_year, holder, is_default, created_at
FROM payment_methods
WHERE user_id = $1
ORDER BY is_default DESC, created_at DESC
`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	methods := make([]paymentdomain.PaymentMethod, 0)
	for rows.Next() {
		var method paymentdomain.PaymentMethod
		var brand string
		if err := rows.Scan(
			&method.ID,
			&method.UserID,
			&brand,
			&method.Last4,
			&method.ExpMonth,
			&method.ExpYear,
			&method.Holder,
			&method.IsDefault,
			&method.CreatedAt,
		); err != nil {
			return nil, err
		}
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
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_methods WHERE user_id = $1`, method.UserID).Scan(&count); err != nil {
		return err
	}
	isDefault := method.IsDefault || count == 0
	if isDefault {
		if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = FALSE WHERE user_id = $1`, method.UserID); err != nil {
			return err
		}
	}

	_, err = tx.ExecContext(ctx, `
INSERT INTO payment_methods (id, user_id, brand, last4, exp_month, exp_year, holder, is_default, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
`, method.ID, method.UserID, string(method.Brand), method.Last4, method.ExpMonth, method.ExpYear, method.Holder, isDefault, method.CreatedAt)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) SetDefaultMethod(ctx context.Context, userID string, methodID string) (*paymentdomain.PaymentMethod, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var exists bool
	if err := tx.QueryRowContext(ctx, `
SELECT EXISTS(SELECT 1 FROM payment_methods WHERE id = $1 AND user_id = $2)
`, methodID, userID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, paymentdomain.ErrPaymentMethodNotFound
	}

	if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = FALSE WHERE user_id = $1`, userID); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payment_methods SET is_default = TRUE WHERE id = $1 AND user_id = $2`, methodID, userID); err != nil {
		return nil, err
	}

	var method paymentdomain.PaymentMethod
	var brand string
	err = tx.QueryRowContext(ctx, `
SELECT id, user_id, brand, last4, exp_month, exp_year, holder, is_default, created_at
FROM payment_methods
WHERE id = $1 AND user_id = $2
`, methodID, userID).Scan(
		&method.ID,
		&method.UserID,
		&brand,
		&method.Last4,
		&method.ExpMonth,
		&method.ExpYear,
		&method.Holder,
		&method.IsDefault,
		&method.CreatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, paymentdomain.ErrPaymentMethodNotFound
	}
	if err != nil {
		return nil, err
	}
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
SELECT is_default FROM payment_methods WHERE id = $1 AND user_id = $2
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
	ORDER BY created_at DESC
	LIMIT 1
)
`, userID); err != nil {
			return err
		}
	}

	return tx.Commit()
}

func (r *PaymentRepository) ListTransactions(ctx context.Context, userID string, limit int) ([]paymentdomain.PaymentTransaction, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, user_id, order_id, title, amount, status, created_at
FROM payment_transactions
WHERE user_id = $1
ORDER BY created_at DESC
LIMIT $2
`, userID, limit)
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

func (r *PaymentRepository) CreateTransaction(ctx context.Context, transaction *paymentdomain.PaymentTransaction) error {
	const query = `
		INSERT INTO payment_transactions (id, user_id, order_id, title, amount, status, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`

	_, err := r.db.ExecContext(ctx, query,
		transaction.ID,
		transaction.UserID,
		transaction.OrderID,
		transaction.Title,
		transaction.Amount,
		transaction.Status,
		transaction.CreatedAt,
	)
	if err != nil {
		return err
	}
	_, err = r.db.ExecContext(ctx, `UPDATE orders SET price_total = cents_to_rub($1), updated_at = NOW() WHERE id = $2`, transaction.Amount, transaction.OrderID)
	return err
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
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, cents_to_rub($9), $10, $11, $12, $13, $14, $15, $16)
ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = payments.updated_at
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	rub_to_cents(amount), currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`
	created, err := scanPayment(tx.QueryRowContext(ctx, query,
		p.ID, p.OrderID, p.DriverID, p.UserID, string(p.Provider), p.ProviderPaymentID, string(p.PaymentMethod), string(p.Purpose),
		p.Amount, p.Currency, string(p.Status), p.ConfirmationURL, p.IdempotencyKey, p.PaidAt, p.CreatedAt, p.UpdatedAt,
	))
	if err != nil {
		return nil, err
	}
	if p.OrderID != nil {
		if _, err := tx.ExecContext(ctx, `UPDATE orders SET price_total = cents_to_rub($1), payment_method = $2, updated_at = NOW() WHERE id = $3`, p.Amount, string(p.PaymentMethod), *p.OrderID); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return created, nil
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
VALUES ($1, NULL, $2, $3, $4, $5, $6, $7, cents_to_rub($8), $9, $10, $11, $12, NULL, $13, $14)
ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = payments.updated_at
RETURNING id, order_id, driver_id, user_id, provider, provider_payment_id, payment_method, purpose,
	rub_to_cents(amount), currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
		p.ID, p.DriverID, p.UserID, string(p.Provider), p.ProviderPaymentID, string(p.PaymentMethod), string(p.Purpose),
		p.Amount, p.Currency, string(p.Status), p.ConfirmationURL, p.IdempotencyKey, p.CreatedAt, p.UpdatedAt,
	))
	if err != nil {
		return nil, err
	}
	_, err = tx.ExecContext(ctx, `
INSERT INTO subscriptions (id, driver_id, plan_id, payment_id, amount, currency, status, starts_at, ends_at, created_at, updated_at)
VALUES ($1, $2, $3, $4, cents_to_rub($5), $6, $7, $8, $9, $10, $11)
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
	rub_to_cents(amount), currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at`,
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

func (r *PaymentRepository) CompleteOrderFinancially(ctx context.Context, orderID, idempotencyKey string, holdSeconds int) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var exists bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM wallet_transactions WHERE idempotency_key = $1)`, idempotencyKey).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return tx.Commit()
	}

	var driverID sql.NullString
	var paymentMethod string
	var orderAmount sql.NullInt64
	err = tx.QueryRowContext(ctx, `
SELECT o.driver_id,
	COALESCE((SELECT payment_method FROM payments WHERE order_id = o.id ORDER BY created_at DESC LIMIT 1), o.payment_method, 'cash'),
	COALESCE(rub_to_cents(o.price_total), (SELECT amount FROM payment_transactions WHERE order_id = o.id ORDER BY created_at DESC LIMIT 1))
FROM orders o
WHERE o.id = $1
FOR UPDATE`, orderID).Scan(&driverID, &paymentMethod, &orderAmount)
	if errors.Is(err, sql.ErrNoRows) {
		return paymentdomain.ErrPaymentNotFound
	}
	if err != nil {
		return err
	}
	if !driverID.Valid || driverID.String == "" {
		return errors.New("order has no driver")
	}
	if !orderAmount.Valid || orderAmount.Int64 <= 0 {
		return errors.New("order amount is missing")
	}

	var paymentID sql.NullString
	var paymentStatus sql.NullString
	_ = tx.QueryRowContext(ctx, `SELECT id, status FROM payments WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1`, orderID).Scan(&paymentID, &paymentStatus)
	if paymentMethod == string(paymentdomain.PaymentMethodCard) && paymentStatus.String != string(paymentdomain.PaymentStatusSucceeded) {
		return errors.New("card payment is not succeeded")
	}

	walletID, err := ensureWalletLocked(ctx, tx, driverID.String)
	if err != nil {
		return err
	}

	total := orderAmount.Int64
	commission := total * 15 / 100
	now := time.Now().UTC()
	if paymentMethod == string(paymentdomain.PaymentMethodCash) {
		if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET debt_balance = debt_balance + cents_to_rub($1), updated_at = NOW() WHERE id = $2`, commission, walletID); err != nil {
			return err
		}
		if err := insertWalletTx(ctx, tx, walletID, driverID.String, &orderID, nullableString(paymentID), nil, paymentdomain.WalletTypeCashCommissionDebt, paymentdomain.WalletDirectionCredit, commission, paymentdomain.WalletTxStatusSucceeded, "Tow Truck commission debt for cash order", idempotencyKey+":cash_debt", nil); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE orders SET financially_completed_at = NOW(), financial_status = 'completed' WHERE id = $1`, orderID)
		if err != nil {
			return err
		}
		return tx.Commit()
	}

	driverAmount := total - commission
	var debt int64
	if err := tx.QueryRowContext(ctx, `SELECT rub_to_cents(debt_balance) FROM driver_wallets WHERE id = $1 FOR UPDATE`, walletID).Scan(&debt); err != nil {
		return err
	}
	repayment := minInt64(driverAmount, debt)
	if repayment > 0 {
		if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET debt_balance = debt_balance - cents_to_rub($1), updated_at = NOW() WHERE id = $2`, repayment, walletID); err != nil {
			return err
		}
		if err := insertWalletTx(ctx, tx, walletID, driverID.String, &orderID, nullableString(paymentID), nil, paymentdomain.WalletTypeDebtRepayment, paymentdomain.WalletDirectionDebit, repayment, paymentdomain.WalletTxStatusSucceeded, "Debt repayment from card order", idempotencyKey+":debt_repayment", nil); err != nil {
			return err
		}
	}
	pending := driverAmount - repayment
	if pending > 0 {
		availableAfter := now.Add(time.Duration(holdSeconds) * time.Second)
		if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET pending_balance = pending_balance + cents_to_rub($1), updated_at = NOW() WHERE id = $2`, pending, walletID); err != nil {
			return err
		}
		if err := insertWalletTx(ctx, tx, walletID, driverID.String, &orderID, nullableString(paymentID), nil, paymentdomain.WalletTypeOrderIncome, paymentdomain.WalletDirectionCredit, pending, paymentdomain.WalletTxStatusPending, "Driver income for card order", idempotencyKey+":order_income", &availableAfter); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE orders SET financially_completed_at = NOW(), financial_status = 'completed' WHERE id = $1`, orderID); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PaymentRepository) ReleasePendingBalances(ctx context.Context, limit int) (int, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, `
SELECT id, wallet_id, driver_id, rub_to_cents(amount), order_id, payment_id
FROM wallet_transactions
WHERE type = 'order_income' AND status = 'pending' AND available_after <= NOW()
ORDER BY created_at ASC
LIMIT $1
FOR UPDATE SKIP LOCKED`, limit)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	type pendingTx struct {
		id, walletID, driverID string
		amount                 int64
		orderID, paymentID     sql.NullString
	}
	var items []pendingTx
	for rows.Next() {
		var item pendingTx
		if err := rows.Scan(&item.id, &item.walletID, &item.driverID, &item.amount, &item.orderID, &item.paymentID); err != nil {
			return 0, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for _, item := range items {
		if _, err := tx.ExecContext(ctx, `SELECT id FROM driver_wallets WHERE id = $1 FOR UPDATE`, item.walletID); err != nil {
			return 0, err
		}
		if _, err := tx.ExecContext(ctx, `
UPDATE driver_wallets
SET pending_balance = pending_balance - cents_to_rub($1), available_balance = available_balance + cents_to_rub($1), updated_at = NOW()
WHERE id = $2`, item.amount, item.walletID); err != nil {
			return 0, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_transactions SET status = 'succeeded' WHERE id = $1`, item.id); err != nil {
			return 0, err
		}
		orderID := nullableString(item.orderID)
		paymentID := nullableString(item.paymentID)
		if err := insertWalletTx(ctx, tx, item.walletID, item.driverID, orderID, paymentID, nil, paymentdomain.WalletTypePendingToAvailable, paymentdomain.WalletDirectionCredit, item.amount, paymentdomain.WalletTxStatusSucceeded, "Released pending income to available balance", "release:"+item.id, nil); err != nil {
			return 0, err
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return len(items), nil
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

func (r *PaymentRepository) ListWalletTransactions(ctx context.Context, driverID string, limit int) ([]paymentdomain.WalletTransaction, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, wallet_id, driver_id, order_id, payment_id, payout_id, type, direction, rub_to_cents(amount), currency, status, description, idempotency_key, available_after, created_at
FROM wallet_transactions
WHERE driver_id = $1
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

func (r *PaymentRepository) ListPayouts(ctx context.Context, driverID string, limit int) ([]paymentdomain.Payout, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT id, driver_id, wallet_id, provider, provider_payout_id, rub_to_cents(amount), currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
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
SELECT id, driver_id, wallet_id, provider, provider_payout_id, rub_to_cents(amount), currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
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
	if err := tx.QueryRowContext(ctx, `SELECT rub_to_cents(available_balance) FROM driver_wallets WHERE id = $1 FOR UPDATE`, walletID).Scan(&available); err != nil {
		return nil, err
	}
	if payout.Amount <= 0 {
		return nil, paymentdomain.ErrInvalidAmount
	}
	if payout.Amount > available {
		return nil, paymentdomain.ErrInsufficientFunds
	}
	payout.WalletID = walletID
	created, err := scanPayout(tx.QueryRowContext(ctx, `
INSERT INTO payouts (id, driver_id, wallet_id, provider, provider_payout_id, amount, currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, cents_to_rub($6), $7, $8, $9, $10, $11, $12, $13)
ON CONFLICT (idempotency_key) WHERE idempotency_key <> '' DO UPDATE SET updated_at = payouts.updated_at
RETURNING id, driver_id, wallet_id, provider, provider_payout_id, rub_to_cents(amount), currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at`,
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
SELECT id, driver_id, wallet_id, provider, provider_payout_id, rub_to_cents(amount), currency, status, failure_reason, idempotency_key, paid_at, created_at, updated_at
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
	if _, err := tx.ExecContext(ctx, `UPDATE driver_wallets SET available_balance = available_balance - cents_to_rub($1), updated_at = NOW() WHERE id = $2`, payout.Amount, payout.WalletID); err != nil {
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

func (r *PaymentRepository) ActivateSubscriptionByPayment(ctx context.Context, paymentID string) error {
	_, err := r.db.ExecContext(ctx, `
UPDATE subscriptions
SET status = 'active', starts_at = COALESCE(starts_at, NOW()), ends_at = COALESCE(ends_at, NOW() + INTERVAL '30 days'), updated_at = NOW()
WHERE payment_id = $1`, paymentID)
	return err
}

func (r *PaymentRepository) CreateRefund(ctx context.Context, refund *paymentdomain.Refund) (*paymentdomain.Refund, error) {
	return scanRefund(r.db.QueryRowContext(ctx, `
INSERT INTO refunds (id, payment_id, provider_refund_id, amount, currency, reason, status, idempotency_key, created_at, updated_at)
VALUES ($1, $2, $3, cents_to_rub($4), $5, $6, $7, $8, $9, $10)
ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = refunds.updated_at
RETURNING id, payment_id, provider_refund_id, rub_to_cents(amount), currency, reason, status, idempotency_key, created_at, updated_at`,
		refund.ID, refund.PaymentID, refund.ProviderRefundID, refund.Amount, refund.Currency, refund.Reason, string(refund.Status), refund.IdempotencyKey, refund.CreatedAt, refund.UpdatedAt))
}

func (r *PaymentRepository) ExportFinanceReport(ctx context.Context, reportType string) ([][]string, error) {
	reportType = strings.ReplaceAll(reportType, "-", "_")
	if reportType == "transactions" {
		reportType = "wallet_transactions"
	}
	queries := map[string]string{
		"orders":              `SELECT id, user_id, COALESCE(driver_id,''), status, rub_to_cents(price_total)::TEXT, payment_method, created_at::TEXT FROM orders ORDER BY created_at DESC`,
		"payments":            `SELECT id, COALESCE(order_id,''), user_id, provider, COALESCE(provider_payment_id,''), payment_method, purpose, rub_to_cents(amount)::TEXT, currency, status, created_at::TEXT FROM payments ORDER BY created_at DESC`,
		"payouts":             `SELECT id, driver_id, rub_to_cents(amount)::TEXT, currency, status, COALESCE(provider_payout_id,''), created_at::TEXT FROM payouts ORDER BY created_at DESC`,
		"wallets":             `SELECT id, driver_id, rub_to_cents(available_balance)::TEXT, rub_to_cents(pending_balance)::TEXT, rub_to_cents(debt_balance)::TEXT, currency, updated_at::TEXT FROM driver_wallets ORDER BY updated_at DESC`,
		"commissions":         `SELECT id, driver_id, COALESCE(order_id,''), type, rub_to_cents(amount)::TEXT, currency, created_at::TEXT FROM wallet_transactions WHERE type IN ('commission','cash_commission_debt','debt_repayment') ORDER BY created_at DESC`,
		"subscriptions":       `SELECT id, driver_id, plan_id, payment_id, rub_to_cents(amount)::TEXT, currency, status, created_at::TEXT FROM subscriptions ORDER BY created_at DESC`,
		"cash_debts":          `SELECT id, driver_id, COALESCE(order_id,''), rub_to_cents(amount)::TEXT, status, created_at::TEXT FROM wallet_transactions WHERE type = 'cash_commission_debt' ORDER BY created_at DESC`,
		"wallet_transactions": `SELECT id, wallet_id, driver_id, COALESCE(order_id,''), COALESCE(payment_id,''), COALESCE(payout_id,''), type, direction, rub_to_cents(amount)::TEXT, currency, status, description, created_at::TEXT FROM wallet_transactions ORDER BY created_at DESC`,
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
	rub_to_cents(amount), currency, status, confirmation_url, idempotency_key, paid_at, created_at, updated_at FROM payments`
}

func walletSelectSQL() string {
	return `SELECT id, driver_id, rub_to_cents(available_balance), rub_to_cents(pending_balance), rub_to_cents(debt_balance), currency, created_at, updated_at FROM driver_wallets`
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
VALUES (gen_random_uuid()::TEXT, $1, $2, $3, $4, $5, $6, $7, cents_to_rub($8), 'RUB', $9, $10, $11, $12, NOW())
ON CONFLICT (idempotency_key) DO NOTHING`,
		walletID, driverID, orderID, paymentID, payoutID, string(typ), string(direction), amount, string(status), description, idempotencyKey, availableAfter)
	return err
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
