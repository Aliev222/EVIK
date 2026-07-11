-- +goose Up
ALTER TABLE orders
    ADD COLUMN driver_amount     BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN commission_amount BIGINT NOT NULL DEFAULT 0;

ALTER TABLE orders ADD CONSTRAINT chk_orders_split
CHECK (financially_completed_at IS NULL
       OR price_total = commission_amount + driver_amount);

CREATE INDEX idx_orders_driver_earnings
    ON orders (driver_id, financially_completed_at DESC)
    WHERE status = 'completed';

-- +goose Down
DROP INDEX IF EXISTS idx_orders_driver_earnings;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_split;
ALTER TABLE orders DROP COLUMN IF EXISTS commission_amount;
ALTER TABLE orders DROP COLUMN IF EXISTS driver_amount;
