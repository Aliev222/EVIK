-- +goose Up
-- +goose StatementBegin

-- Maximum allowed driver cash debt before the driver is blocked from working.
-- Value is in kopecks: 100000 = 1000 RUB. 0 disables the debt gate.
INSERT INTO platform_settings (key, value, description) VALUES
    ('max_cash_debt_kopecks', '100000', 'Макс. долг водителя за наличные, копейки (0 = отключено)')
ON CONFLICT (key) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
DELETE FROM platform_settings WHERE key = 'max_cash_debt_kopecks';