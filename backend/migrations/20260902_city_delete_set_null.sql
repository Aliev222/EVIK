-- +goose Up
-- Allow deleting a city/zone even when orders reference it. Existing orders
-- keep their coordinates and continue their lifecycle; their city_id is set
-- to NULL so the dispatcher falls back to a radius search. New orders in the
-- deleted zone are impossible because the zone no longer passes CheckPoint.

-- Drop whatever FK constraint currently protects orders.city_id (its auto name
-- is orders_city_id_fkey, but we find it dynamically to be robust).
DO $$
DECLARE
    con_name text;
BEGIN
    SELECT conname INTO con_name
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE t.relname = 'orders'
      AND a.attname = 'city_id'
      AND c.contype = 'f'
    LIMIT 1;

    IF con_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE orders DROP CONSTRAINT %I', con_name);
    END IF;
END $$;

ALTER TABLE orders ADD CONSTRAINT orders_city_id_fkey
    FOREIGN KEY (city_id) REFERENCES service_areas(id) ON DELETE SET NULL;

-- +goose Down
DO $$
DECLARE
    con_name text;
BEGIN
    SELECT conname INTO con_name
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE t.relname = 'orders'
      AND a.attname = 'city_id'
      AND c.contype = 'f'
    LIMIT 1;

    IF con_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE orders DROP CONSTRAINT %I', con_name);
    END IF;
END $$;

ALTER TABLE orders ADD CONSTRAINT orders_city_id_fkey
    FOREIGN KEY (city_id) REFERENCES service_areas(id);
