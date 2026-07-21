-- +goose Up
-- Recompute bbox from center+radius so the bbox fully contains the haversine
-- circle. Previously the bbox came from Nominatim (often narrow / offset),
-- causing CheckPoint to reject valid points at the SQL prefilter stage.
UPDATE service_areas SET
    min_lat = center_lat - (radius_km / 6371.0 * 180 / pi()),
    max_lat = center_lat + (radius_km / 6371.0 * 180 / pi()),
    min_lng = center_lng - (radius_km / (6371.0 * cos(radians(center_lat))) * 180 / pi()),
    max_lng = center_lng + (radius_km / (6371.0 * cos(radians(center_lat))) * 180 / pi())
WHERE center_lat IS NOT NULL;

-- +goose Down
-- No-op: the old bbox values cannot be recovered from this migration alone.
