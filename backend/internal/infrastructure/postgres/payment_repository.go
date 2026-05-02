package postgres

import (
	"context"
	"database/sql"
	"errors"

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

	return err
}
