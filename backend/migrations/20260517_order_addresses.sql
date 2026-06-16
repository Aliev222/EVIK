-- +goose Up
-- Add pickup/dropoff address strings captured at order creation time.
-- Nullable so existing rows (which only have lat/lng) remain valid.
ALTER TABLE orders
    ADD COLUMN IF NOT EXISTS pickup_address  TEXT,
    ADD COLUMN IF NOT EXISTS dropoff_address TEXT;

-- +goose Down
ALTER TABLE orders
    DROP COLUMN IF EXISTS pickup_address,
    DROP COLUMN IF EXISTS dropoff_address;
