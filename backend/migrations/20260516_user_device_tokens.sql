-- +goose Up
CREATE TABLE IF NOT EXISTS user_device_tokens (
	fcm_token TEXT PRIMARY KEY,
	user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	role TEXT NOT NULL CHECK (role IN ('client', 'driver', 'admin')),
	platform TEXT NOT NULL DEFAULT '',
	app_version TEXT NOT NULL DEFAULT '',
	revoked_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user_role
	ON user_device_tokens (user_id, role)
	WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_role_active
	ON user_device_tokens (role)
	WHERE revoked_at IS NULL;

-- +goose Down
SELECT 1;
