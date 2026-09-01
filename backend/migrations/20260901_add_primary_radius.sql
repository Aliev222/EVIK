-- +goose Up
ALTER TABLE service_areas
    ADD COLUMN primary_radius_km DOUBLE PRECISION DEFAULT 50.0;

-- Set primary_radius_km from existing radius_km for all zones
UPDATE service_areas SET primary_radius_km = radius_km WHERE primary_radius_km IS NULL;

ALTER TABLE service_areas
    ALTER COLUMN primary_radius_km SET NOT NULL;

-- +goose Down
ALTER TABLE service_areas
    DROP COLUMN IF EXISTS primary_radius_km;
