-- City-based order routing: bind each order to the service area it was placed in.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS city_id TEXT REFERENCES service_areas(id);
CREATE INDEX IF NOT EXISTS idx_orders_city_status ON orders (city_id, status);
