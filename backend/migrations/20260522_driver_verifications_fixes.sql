-- +goose Up
ALTER TABLE driver_verifications
    ADD COLUMN IF NOT EXISTS admin_comments TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE driver_verifications
    DROP COLUMN IF EXISTS admin_comments;
