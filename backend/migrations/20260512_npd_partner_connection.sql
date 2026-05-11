-- Phase 6: Self-employed driver connection to Moy Nalog (FNS NPD Partner API).
-- Extends existing driver_tax_profiles with fields required to store
-- the OAuth2 tokens issued by FNS after the driver grants partner access
-- in the Moy Nalog mobile app. No new tables are introduced.

ALTER TABLE driver_tax_profiles
	ADD COLUMN IF NOT EXISTS npd_access_token TEXT,
	ADD COLUMN IF NOT EXISTS npd_refresh_token TEXT,
	ADD COLUMN IF NOT EXISTS npd_token_expires_at TIMESTAMPTZ,
	ADD COLUMN IF NOT EXISTS npd_connected_at TIMESTAMPTZ,
	ADD COLUMN IF NOT EXISTS npd_revoked_at TIMESTAMPTZ,
	ADD COLUMN IF NOT EXISTS npd_connection_status TEXT NOT NULL DEFAULT 'not_connected';

ALTER TABLE driver_tax_profiles
	DROP CONSTRAINT IF EXISTS driver_tax_profiles_npd_status;

ALTER TABLE driver_tax_profiles
	ADD CONSTRAINT driver_tax_profiles_npd_status
		CHECK (npd_connection_status IN ('not_connected', 'connected', 'revoked', 'error'));

CREATE INDEX IF NOT EXISTS idx_driver_tax_profiles_npd_status
	ON driver_tax_profiles (npd_connection_status, updated_at DESC);

-- Admin can override the official FNS full name for display purposes.
-- The official name from FNS is mirrored into users.full_name when the
-- driver successfully connects Moy Nalog, but we keep the raw FNS value
-- alongside the admin-entered display name for audit / accounting.
ALTER TABLE users
	ADD COLUMN IF NOT EXISTS fns_full_name TEXT;
