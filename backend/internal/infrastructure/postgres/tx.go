package postgres

import (
	"context"
	"database/sql"
)

// WithTx opens a transaction and calls fn. If fn returns an error the
// transaction is rolled back; otherwise it is committed.
// When db is nil (test mode) fn is called with a nil tx — callers should
// handle this by falling back to their non-tx methods.
func WithTx(ctx context.Context, db *sql.DB, fn func(*sql.Tx) error) error {
	if db == nil {
		return fn(nil)
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit()
}
