-- +goose Up
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancel_reason TEXT;

-- +goose Down
ALTER TABLE orders DROP COLUMN IF EXISTS cancel_reason;
