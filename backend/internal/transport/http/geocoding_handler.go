package http

import (
	"context"
	"errors"
	"net/http"

	"evik/backend/internal/infrastructure/geocoding"
)

// ReverseGeocoder resolves coordinates into a human-readable address.
type ReverseGeocoder interface {
	Reverse(ctx context.Context, lat, lng float64) (*geocoding.ReverseResult, error)
}

// GeocodingHandler exposes address-geocoding endpoints to authenticated
// clients. Reverse geocoding for critical client flows must go through the
// Авро backend — the app never talks directly to public OSM/Nominatim for
// addresses (user-agent and the 1 req/s policy are owned by the backend).
type GeocodingHandler struct {
	geocoder ReverseGeocoder
}

func NewGeocodingHandler(geocoder ReverseGeocoder) *GeocodingHandler {
	return &GeocodingHandler{geocoder: geocoder}
}

// @Summary      Reverse geocode coordinates
// @Description  Resolves a latitude/longitude point into a human-readable address via the configured Nominatim instance. Requires authentication.
// @Tags         geocoding
// @Produce      json
// @Security     BearerAuth
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
