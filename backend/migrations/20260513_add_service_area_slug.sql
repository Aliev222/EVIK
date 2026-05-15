-- +goose Up
-- Add slug column to service_areas table
-- Migration: 20260513_add_service_area_slug.sql

-- Add slug column
ALTER TABLE service_areas
ADD COLUMN slug VARCHAR(255);

-- Create index for better performance
CREATE INDEX idx_service_areas_slug ON service_areas(slug);

-- Add some example data if service_areas table is empty
INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
SELECT
  gen_random_uuid()::text,
  'Махачкала',
  'makhachkala-default',
  42.85,
  47.58,
  42.93,
  47.68,
  true,
  NOW(),
  NOW()
WHERE NOT EXISTS (SELECT 1 FROM service_areas);

INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
SELECT
  gen_random_uuid()::text,
  'Каспийск',
  'kaspiysk-default',
  42.83,
  47.60,
  42.88,
  47.65,
  true,
  NOW(),
  NOW()
WHERE (SELECT COUNT(*) FROM service_areas) = 1;

INSERT INTO service_areas (id, name, slug, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
SELECT
  gen_random_uuid()::text,
  'Дербент',
  'derbent-default',
  42.0,
  48.0,
  42.1,
  48.1,
  false,
  NOW(),
  NOW()
WHERE (SELECT COUNT(*) FROM service_areas) = 2;

-- +goose Down
-- not implemented (forward-only migration)
SELECT 1;