-- +goose Up
-- Check for existing violations before applying constraint:
-- SELECT count(*) FROM orders WHERE status='completed' AND financially_completed_at IS NULL;
ALTER TABLE orders ADD CONSTRAINT chk_orders_completed_financially
CHECK (status <> 'completed' OR financially_completed_at IS NOT NULL);

-- +goose Down
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_completed_financially;
