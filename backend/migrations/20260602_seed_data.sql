-- +goose Up
-- +goose StatementBegin

-- ============================================================
-- SEED: service_areas
-- ============================================================
INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
SELECT gen_random_uuid()::text, 'Махачкала', 'makhachkala-default', 42.85, 47.58, 42.93, 47.68, true, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM service_areas WHERE slug = 'makhachkala-default');

INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
SELECT gen_random_uuid()::text, 'Каспийск', 'kaspiysk-default', 42.83, 47.60, 42.88, 47.65, true, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM service_areas WHERE slug = 'kaspiysk-default');

INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
SELECT gen_random_uuid()::text, 'Дербент', 'derbent-default', 42.0, 48.0, 42.1, 48.1, false, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM service_areas WHERE slug = 'derbent-default');

-- ============================================================
-- SEED: commission_rules
-- ============================================================
INSERT INTO commission_rules (id, name, percent, currency, is_active, starts_at, created_at)
VALUES ('tow-truck-default-commission', 'Tow Truck default marketplace commission', 15.00, 'RUB', TRUE, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- SEED: pricing_tariffs
-- ============================================================
INSERT INTO pricing_tariffs (id, tow_truck_type, base_price, price_per_km, minimum_price, is_active, created_at, updated_at)
VALUES
    ('tariff-winch', 'winch', 250000, 5000, 250000, true, NOW(), NOW()),
    ('tariff-platform', 'platform', 300000, 6000, 300000, true, NOW(), NOW()),
    ('tariff-manipulator', 'manipulator', 400000, 8000, 400000, true, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- SEED: platform_settings
-- ============================================================
INSERT INTO platform_settings (key, value, description) VALUES
    ('commission_percent', '15.00', 'Комиссия платформы, %'),
    ('payout_mode', '"manual"', 'Режим выплат: auto или manual'),
    ('offer_timeout_seconds', '30', 'Таймаут оффера для водителя, секунд'),
    ('dispatch_round_limit', '3', 'Лимит раундов диспетчеризации'),
    ('min_withdrawal_kopecks', '100000', 'Мин. сумма вывода, копейки'),
    ('driver_subscription_daily_price', '50000', 'Подписка: сутки (ввод в ₽, хранение в копейках)'),
    ('driver_subscription_weekly_price', '250000', 'Подписка: неделя (ввод в ₽, хранение в копейках)'),
    ('driver_subscription_monthly_price', '900000', 'Подписка: месяц (ввод в ₽, хранение в копейках)'),
    ('max_cash_debt_kopecks', '100000', 'Макс. долг водителя за наличные, копейки (0 = отключено)')
ON CONFLICT (key) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
DELETE FROM platform_settings;
DELETE FROM pricing_tariffs;
DELETE FROM commission_rules;
DELETE FROM service_areas;
