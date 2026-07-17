-- +goose Up
ALTER TABLE service_areas
    ADD COLUMN center_lat DOUBLE PRECISION,
    ADD COLUMN center_lng DOUBLE PRECISION,
    ADD COLUMN radius_km  DOUBLE PRECISION;

-- 1. Correct coordinates for real cities by slug (UNIQUE, stable)
UPDATE service_areas SET center_lat=42.9764, center_lng=47.5024, radius_km=25
    WHERE slug='makhachkala-default';
UPDATE service_areas SET center_lat=42.8817, center_lng=47.6406, radius_km=15
    WHERE slug='kaspiysk-default';
UPDATE service_areas SET center_lat=42.0678, center_lng=48.2905, radius_km=20
    WHERE slug='derbent-default';

-- 2. Frankfurt — testing zone for owner (VPN in Germany, cannot test from Makhachkala)
UPDATE service_areas SET
    center_lat = 50.1109,
    center_lng = 8.6821,
    radius_km  = 25,
    name = 'Frankfurt (TEST)'
WHERE slug = 'frankfurt-am-main-hessen-deutschland';

-- 3. Moscow — garbage from B-49 fallback bug (already fixed)
DELETE FROM service_areas
WHERE slug = 'moskva-tsentralnyy-federalnyy-okrug-rossiya';

-- 4. Safety net: any remaining row without a center gets one from its bbox
UPDATE service_areas SET
    center_lat = (min_lat + max_lat) / 2,
    center_lng = (min_lng + max_lng) / 2,
    radius_km  = 25
WHERE center_lat IS NULL;

ALTER TABLE service_areas
    ALTER COLUMN center_lat SET NOT NULL,
    ALTER COLUMN center_lng SET NOT NULL,
    ALTER COLUMN radius_km  SET NOT NULL;

-- Old bbox columns kept for backward compatibility (FCM broadcast, etc.)

-- +goose Down
ALTER TABLE service_areas
    DROP COLUMN IF EXISTS center_lat,
    DROP COLUMN IF EXISTS center_lng,
    DROP COLUMN IF EXISTS radius_km;
