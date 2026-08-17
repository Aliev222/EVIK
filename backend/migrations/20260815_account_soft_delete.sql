-- +goose Up
-- Account deletion uses soft-delete + anonymization: the users row is kept
-- (orders/payments/payouts reference it for tax/legal retention) but its PII
-- is replaced and login is disabled. deleted_at marks the irreversible flip.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- +goose Down
ALTER TABLE users DROP COLUMN IF EXISTS deleted_at;