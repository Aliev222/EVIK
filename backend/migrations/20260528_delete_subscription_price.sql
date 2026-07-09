-- +goose Up
DELETE FROM platform_settings WHERE key = 'subscription_price';

-- +goose Down
INSERT INTO platform_settings (key, value, description)
VALUES ('subscription_price', '0', 'Цена подписки для водителя, копейки')
ON CONFLICT (key) DO NOTHING;
