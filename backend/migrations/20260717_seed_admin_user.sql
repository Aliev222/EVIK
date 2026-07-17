-- +goose Up
INSERT INTO users (id, phone, role, full_name, status, created_at, updated_at)
SELECT 'admin', '+70000000000', 'admin', 'Admin', 'active', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = 'admin');

-- +goose Down
DELETE FROM users WHERE id = 'admin' AND role = 'admin';
