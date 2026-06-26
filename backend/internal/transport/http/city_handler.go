package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	servicearea "evik/backend/internal/domain/servicearea"
	"evik/backend/internal/infrastructure/geocoding"

	"github.com/go-chi/chi/v5"
)

// CityGeocoder resolves a city name to a bounding box via an external service.
type CityGeocoder interface {
	SearchCity(ctx context.Context, name string) (*geocoding.CitySearchResult, error)
	Search(ctx context.Context, query string, limit int) ([]geocoding.CitySearchResult, error)
}

// CityIDGenerator generates unique identifiers for new service areas.
type CityIDGenerator interface {
	NewID() string
}

// CityHandler exposes admin CRUD over service areas ("cities"). All routes are
// expected to be mounted behind an admin-role guard in the router.
type CityHandler struct {
	repo     servicearea.Repository
	geocoder CityGeocoder
	idGen    CityIDGenerator
}

func NewCityHandler(repo servicearea.Repository, geocoder CityGeocoder, idGen CityIDGenerator) *CityHandler {
	return &CityHandler{repo: repo, geocoder: geocoder, idGen: idGen}
}

type cityNameRequest struct {
	Name string `json:"name"`
}

type bboxPayload struct {
	MinLat float64 `json:"min_lat"`
	MaxLat float64 `json:"max_lat"`
	MinLng float64 `json:"min_lng"`
	MaxLng float64 `json:"max_lng"`
}

type centerPayload struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// Search geocodes a name via Nominatim and returns a preview without saving.
// POST /admin/cities/search
func (h *CityHandler) Search(w http.ResponseWriter, r *http.Request) {
	name, ok := h.decodeName(w, r)
	if !ok {
		return
	}
	res, err := h.geocoder.SearchCity(r.Context(), name)
	if err != nil {
		h.writeGeocodeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"display_name": res.DisplayName,
		"bbox": bboxPayload{
			MinLat: res.MinLat,
			MaxLat: res.MaxLat,
			MinLng: res.MinLng,
			MaxLng: res.MaxLng,
		},
		"center":         centerPayload{Lat: res.CenterLat, Lng: res.CenterLng},
		"suggested_slug": res.Slug,
	})
}

// autocompleteResult is the JSON shape returned per suggestion.
type autocompleteResult struct {
	DisplayName string  `json:"display_name"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
	MinLat      float64 `json:"min_lat"`
	MaxLat      float64 `json:"max_lat"`
	MinLng      float64 `json:"min_lng"`
	MaxLng      float64 `json:"max_lng"`
	Type        string  `json:"type"`
	OSMID       string  `json:"osm_id"`
}

// Autocomplete returns up to 5 Nominatim suggestions for a partial city name.
// GET /admin/cities/autocomplete?q=...
func (h *CityHandler) Autocomplete(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if len([]rune(q)) < 3 {
		writeJSON(w, http.StatusOK, []autocompleteResult{})
		return
	}

	results, err := h.geocoder.Search(r.Context(), q, 5)
	if err != nil {
		h.writeGeocodeError(w, err)
		return
	}

	out := make([]autocompleteResult, 0, len(results))
	for _, res := range results {
		out = append(out, autocompleteResult{
			DisplayName: res.DisplayName,
			Lat:         res.CenterLat,
			Lng:         res.CenterLng,
			MinLat:      res.MinLat,
			MaxLat:      res.MaxLat,
			MinLng:      res.MinLng,
			MaxLng:      res.MaxLng,
			Type:        res.Type,
			OSMID:       res.OSMID,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

// Create geocodes a name, rejects duplicate slugs, and persists an active area.
// POST /admin/cities
func (h *CityHandler) Create(w http.ResponseWriter, r *http.Request) {
	name, ok := h.decodeName(w, r)
	if !ok {
		return
	}
	res, err := h.geocoder.SearchCity(r.Context(), name)
	if err != nil {
		h.writeGeocodeError(w, err)
		return
	}

	exists, err := h.repo.ExistsBySlug(r.Context(), res.Slug)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if exists {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "city with this slug already exists", "slug": res.Slug})
		return
	}

	area := servicearea.ServiceArea{
		ID:       h.idGen.NewID(),
		Name:     name,
		Slug:     res.Slug,
		MinLat:   res.MinLat,
		MinLng:   res.MinLng,
		MaxLat:   res.MaxLat,
		MaxLng:   res.MaxLng,
		IsActive: true,
	}
	if err := h.repo.Create(r.Context(), area); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"city": cityResponse(area)})
}

// List returns all service areas, active and inactive.
// GET /admin/cities
func (h *CityHandler) List(w http.ResponseWriter, r *http.Request) {
	areas, err := h.repo.List(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	cities := make([]map[string]any, 0, len(areas))
	for _, a := range areas {
		cities = append(cities, cityResponse(a))
	}
	writeJSON(w, http.StatusOK, map[string]any{"cities": cities})
}

type cityPatchRequest struct {
	IsActive *bool `json:"is_active"`
}

// Patch toggles is_active for a city and returns the updated record.
// PATCH /admin/cities/{id}
func (h *CityHandler) Patch(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id is required"})
		return
	}
	var req cityPatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if req.IsActive == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "is_active is required"})
		return
	}
	if err := h.repo.SetActive(r.Context(), id, *req.IsActive); err != nil {
		if errors.Is(err, servicearea.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	updated, err := h.repo.GetByID(r.Context(), id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"city": cityResponse(*updated)})
}

// Delete hard-deletes a city unless it still has active orders within bounds.
// DELETE /admin/cities/{id}
func (h *CityHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id is required"})
		return
	}
	if err := h.repo.Delete(r.Context(), id); err != nil {
		switch {
		case errors.Is(err, servicearea.ErrAreaHasActiveOrders):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "Cannot delete: city has active orders"})
		case errors.Is(err, servicearea.ErrNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found"})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

// decodeName parses and validates a { "name": "..." } body.
func (h *CityHandler) decodeName(w http.ResponseWriter, r *http.Request) (string, bool) {
	var req cityNameRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return "", false
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
		return "", false
	}
	return name, true
}

// writeGeocodeError maps geocoding failures to client-facing statuses.
func (h *CityHandler) writeGeocodeError(w http.ResponseWriter, err error) {
	if errors.Is(err, geocoding.ErrCityNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found by geocoder"})
		return
	}
	writeJSON(w, http.StatusBadGateway, map[string]string{"error": "geocoding failed: " + err.Error()})
}

// cityResponse renders a service area as the public city JSON shape.
func cityResponse(a servicearea.ServiceArea) map[string]any {
	return map[string]any{
		"id":   a.ID,
		"name": a.Name,
		"slug": a.Slug,
		"bbox": bboxPayload{
			MinLat: a.MinLat,
			MaxLat: a.MaxLat,
			MinLng: a.MinLng,
			MaxLng: a.MaxLng,
		},
		"is_active": a.IsActive,
	}
}
