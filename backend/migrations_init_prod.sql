-- migrations_init_prod.sql
--
-- ONE-TIME initialization script for the goose migration tracker.
--
-- Run this script ONCE on the production database BEFORE deploying the
-- version of the backend that includes the embedded goose runner.
--
-- Why: all 6 migrations in backend/migrations/ were applied to production
-- manually before goose was introduced. Without this script, goose would
-- see an empty goose_db_version table on first start and try to apply
-- every migration again. The SQL is idempotent and would likely succeed,
-- but we explicitly mark the existing migrations as already applied to
-- avoid any risk of side effects (re-running INSERTs, re-creating
-- functions, etc.).
--
-- After this script runs once, goose will only apply NEW migrations
-- added after 20260515.

BEGIN;

-- Create the goose tracking table (same schema goose itself would create).
CREATE TABLE IF NOT EXISTS goose_db_version (
    id          SERIAL PRIMARY KEY,
    version_id  BIGINT NOT NULL,
    is_applied  BOOLEAN NOT NULL,
    tstamp      TIMESTAMP NULL DEFAULT NOW()
);

-- The "zero" baseline row goose expects to exist.
INSERT INTO goose_db_version (version_id, is_applied)
SELECT 0, TRUE
WHERE NOT EXISTS (SELECT 1 FROM goose_db_version WHERE version_id = 0);

-- Mark the 6 pre-existing migrations as already applied.
INSERT INTO goose_db_version (version_id, is_applied)
SELECT v, TRUE
FROM (VALUES
    (20260510::BIGINT),
    (20260511::BIGINT),
    (20260512::BIGINT),
    (20260513::BIGINT),
    (20260514::BIGINT),
    (20260515::BIGINT)
) AS m(v)
WHERE NOT EXISTS (
    SELECT 1 FROM goose_db_version gdv WHERE gdv.version_id = m.v
);

COMMIT;

-- Verification query — should return 7 rows (baseline + 6 migrations),
-- all with is_applied = true.
SELECT version_id, is_applied, tstamp
FROM goose_db_version
ORDER BY version_id;
