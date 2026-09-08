package http

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"evik/backend/internal/infrastructure/geocoding"
)

// ReverseGeocoder resolves coordinates into a human-readable address.
type ReverseGeocoder interface {
	Reverse(ctx context.Context, lat, lng float64) (*geocoding.ReverseResult, error)
}

// Geocoder resolves both address text and coordinates. Keeping both flows in
// the backend ensures the mobile app never needs to call public Nominatim
// directly and lets production switch to a self-hosted provider by config.
type Geocoder interface {
	ReverseGeocoder
	Search(ctx context.Context, query string, limit int) ([]geocoding.CitySearchResult, error)
}

// GeocodingHandler exposes public, rate-limited address-geocoding endpoints.
// Reverse geocoding for critical client flows must go through the
// Авро backend — the app never talks directly to public OSM/Nominatim for
// addresses (user-agent and the 1 req/s policy are owned by the backend).
type GeocodingHandler struct {
	geocoder Geocoder
}

func NewGeocodingHandler(geocoder Geocoder) *GeocodingHandler {
	return &GeocodingHandler{geocoder: geocoder}
}

type geocodingSearchResult struct {
	DisplayName string  `json:"display_name"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
}

// Search resolves address text into a short list of normalized coordinates.
func (h *GeocodingHandler) Search(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if len([]rune(query)) < 3 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "q must contain at least 3 characters"})
		return
	}

	limit := 5
	if rawLimit := r.URL.Query().Get("limit"); rawLimit != "" {
		parsed, err := strconv.Atoi(rawLimit)
		if err != nil || parsed < 1 || parsed > 5 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "limit must be in [1,5]"})
			return
		}
		limit = parsed
	}

	results, err := h.geocoder.Search(r.Context(), query, limit)
	if err != nil {
		writeUpstreamError(w, http.StatusBadGateway, err)
		return
	}

	payload := make([]geocodingSearchResult, 0, len(results))
	for _, result := range results {
		payload = append(payload, geocodingSearchResult{
			DisplayName: result.DisplayName,
			Lat:         result.CenterLat,
			Lng:         result.CenterLng,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": payload})
}

// @Summary      Reverse geocode coordinates
// @Description  Resolves a latitude/longitude point into a human-readable address via the configured Nominatim instance.
// @Tags         geocoding
// @Produce      json
// @Param        lat  query  number  true  "Latitude (WGS84)"
// @Param        lng  query  number  true  "Longitude (WGS84)"
// @Success      200  {object}  map[string]any  {"address": "human-readable address"}
// @Failure      400  {object}  ErrorResponse  "missing or invalid parameters"
// @Failure      404  {object}  ErrorResponse  "no address for the point"
// @Failure      502  {object}  ErrorResponse  "geocoder failed"
// @Router       /geocode/reverse [get]
func (h *GeocodingHandler) Reverse(w http.ResponseWriter, r *http.Request) {
	lat, ok := parseRequiredFloatQuery(w, r, "lat")
	if !ok {
		return
	}
	lng, ok := parseRequiredFloatQuery(w, r, "lng")
	if !ok {
		return
	}

	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "lat must be in [-90,90] and lng in [-180,180]",
		})
		return
	}

	result, err := h.geocoder.Reverse(r.Context(), lat, lng)
	if err != nil {
		if errors.Is(err, geocoding.ErrReverseNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "address not found"})
			return
		}
		writeUpstreamError(w, http.StatusBadGateway, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"address": result.DisplayName})
}
