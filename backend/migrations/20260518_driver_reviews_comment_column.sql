-- +goose Up
-- Reconcile the driver_reviews schema on databases that were created by the
-- legacy ensureSchema() (which used a "text" column) before this fix moved the
-- canonical table definition fully into 20260515_driver_reviews.sql ("comment").
--
-- Idempotent and safe to run on:
--   * legacy prod DBs   -> "text" exists, "comment" missing  -> rename text->comment
--   * fresh DBs         -> "comment" already exists           -> no-op
--   * partial/unknown   -> neither exists                     -> add "comment"
-- +goose StatementBegin
DO $$
BEGIN
    -- Case 1: legacy schema has "text" but not "comment" -> rename in place
    -- (preserves existing review bodies).
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'driver_reviews' AND column_name = 'text'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'driver_reviews' AND column_name = 'comment'
    ) THEN
        ALTER TABLE driver_reviews RENAME COLUMN text TO comment;
    END IF;

    -- Case 2: neither column present -> add "comment".
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'driver_reviews' AND column_name = 'comment'
    ) THEN
        ALTER TABLE driver_reviews ADD COLUMN comment TEXT DEFAULT '';
    END IF;

    -- "comment" must be nullable (legacy "text" was NOT NULL DEFAULT '').
    -- Drop the NOT NULL constraint if it survived the rename.
    ALTER TABLE driver_reviews ALTER COLUMN comment DROP NOT NULL;

    -- Ensure updated_at exists (legacy ensureSchema table lacked it; the
    -- canonical 20260515 definition includes it).
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'driver_reviews' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE driver_reviews ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    END IF;
END $$;
-- +goose StatementEnd

-- +goose Down
-- Forward-only migration; no rollback (renaming back would risk data loss on
-- DBs that always had "comment").
SELECT 1;
