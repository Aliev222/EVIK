-- +goose Up
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_expanded BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS expanded_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_orders_expansion_check
    ON orders (created_at)
    WHERE status = 'searching' AND is_expanded = FALSE;

-- +goose Down
DROP INDEX IF EXISTS idx_orders_expansion_check;
ALTER TABLE orders DROP COLUMN IF EXISTS expanded_at;
ALTER TABLE orders DROP COLUMN IF EXISTS is_expanded;
