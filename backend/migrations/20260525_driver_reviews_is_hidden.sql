-- +goose Up
ALTER TABLE driver_reviews ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE driver_reviews DROP COLUMN IF EXISTS is_hidden;
