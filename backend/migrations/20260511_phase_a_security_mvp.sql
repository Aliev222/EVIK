-- +goose Up
CREATE TABLE IF NOT EXISTS users (
	id TEXT PRIMARY KEY,
	phone TEXT NOT NULL,
	full_name TEXT NOT NULL,
	role TEXT NOT NULL,
	password_hash TEXT,
	status TEXT NOT NULL DEFAULT 'active',
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_role ON users (phone, role);
CREATE INDEX IF NOT EXISTS idx_users_role_status ON users (role, status);

CREATE TABLE IF NOT EXISTS user_refresh_sessions (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	role TEXT NOT NULL,
	token_hash TEXT NOT NULL UNIQUE,
	expires_at TIMESTAMPTZ NOT NULL,
	revoked_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_user_created ON user_refresh_sessions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_active_hash ON user_refresh_sessions (token_hash) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS phone_otps (
	id TEXT PRIMARY KEY,
	phone TEXT NOT NULL,
	role TEXT NOT NULL,
	code_hash TEXT NOT NULL,
	expires_at TIMESTAMPTZ NOT NULL,
	consumed_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_phone_otps_lookup ON phone_otps (phone, role, created_at DESC);

CREATE TABLE IF NOT EXISTS service_areas (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	min_lat DOUBLE PRECISION NOT NULL,
	min_lng DOUBLE PRECISION NOT NULL,
	max_lat DOUBLE PRECISION NOT NULL,
	max_lng DOUBLE PRECISION NOT NULL,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_service_areas_active_bounds ON service_areas (is_active, min_lat, max_lat, min_lng, max_lng);

INSERT INTO service_areas (id, name, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
VALUES ('moscow-default', 'Moscow default area', 55.20, 36.80, 56.20, 38.40, TRUE, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET is_active = EXCLUDED.is_active, updated_at = NOW();

CREATE TABLE IF NOT EXISTS driver_tax_profiles (
	driver_id TEXT PRIMARY KEY,
	inn TEXT NOT NULL,
	taxpayer_type TEXT NOT NULL,
	verification_status TEXT NOT NULL DEFAULT 'pending',
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	CONSTRAINT driver_tax_profiles_inn_format CHECK (inn ~ '^[0-9]{10}([0-9]{2})?$'),
	CONSTRAINT driver_tax_profiles_taxpayer_type CHECK (taxpayer_type IN ('self_employed', 'ip')),
	CONSTRAINT driver_tax_profiles_status CHECK (verification_status IN ('pending', 'verified', 'rejected'))
);

CREATE INDEX IF NOT EXISTS idx_driver_tax_profiles_status ON driver_tax_profiles (verification_status, updated_at DESC);

-- +goose Down
-- not implemented (forward-only migration)
SELECT 1;
