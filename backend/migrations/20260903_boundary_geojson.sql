-- +goose Up
ALTER TABLE service_areas
    ADD COLUMN boundary_geojson TEXT;

ALTER TABLE service_areas
    ADD COLUMN boundary_buffer_km DOUBLE PRECISION DEFAULT 7.0;

-- +goose Down
ALTER TABLE service_areas
    DROP COLUMN IF EXISTS boundary_buffer_km;

ALTER TABLE service_areas
    DROP COLUMN IF EXISTS boundary_geojson;
