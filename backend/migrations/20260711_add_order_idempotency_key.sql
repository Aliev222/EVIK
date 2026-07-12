-- +goose Up
ALTER TABLE orders ADD COLUMN idempotency_key TEXT NOT NULL DEFAULT '';
CREATE UNIQUE INDEX idx_orders_idempotency_key ON orders (idempotency_key) WHERE idempotency_key <> '';

-- +goose Down
DROP INDEX IF EXISTS idx_orders_idempotency_key;
ALTER TABLE orders DROP COLUMN IF EXISTS idempotency_key;
