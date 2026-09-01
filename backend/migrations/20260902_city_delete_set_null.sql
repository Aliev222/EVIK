-- +goose Up
-- Allow deleting a city/zone even when orders reference it. Existing orders
-- keep their coordinates and continue their lifecycle; their city_id is set
-- to NULL so the dispatcher falls back to a radius search. New orders in the
-- deleted zone are impossible because the zone no longer passes CheckPoint.
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_city_id_fkey;
ALTER TABLE orders ADD CONSTRAINT orders_city_id_fkey
    FOREIGN KEY (city_id) REFERENCES service_areas(id) ON DELETE SET NULL;

-- +goose Down
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_city_id_fkey;
ALTER TABLE orders ADD CONSTRAINT orders_city_id_fkey
    FOREIGN KEY (city_id) REFERENCES service_areas(id);
