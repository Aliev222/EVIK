-- +goose Up
ALTER TABLE orders ADD COLUMN IF NOT EXISTS city_id TEXT REFERENCES service_areas(id);
CREATE INDEX IF NOT EXISTS idx_orders_city_status ON orders (city_id, status);

-- +goose Down
DROP INDEX IF EXISTS idx_orders_city_status;
ALTER TABLE orders DROP COLUMN IF EXISTS city_id;
