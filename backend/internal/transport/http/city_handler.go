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
	Name            string `json:"name"`
	PrimaryRadiusKM float64 `json:"primary_radius_km"`
	BoundaryBufferKM float64 `json:"boundary_buffer_km"`
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

// @Summary      Search city (admin)
// @Description  Geocodes a city name via Nominatim and returns a preview with bounding box and center coordinates.
// @Tags         cities
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CityNameRequest  true  "City name to search"
// @Success      200  {object}  map[string]any  "city geocoding result"
// @Failure      400  {object}  ErrorResponse  "invalid request"
// @Failure      404  {object}  ErrorResponse  "city not found"
// @Router       /admin/cities/search [post]
func (h *CityHandler) Search(w http.ResponseWriter, r *http.Request) {
	req, ok := h.decodeCityRequest(w, r)
	if !ok {
		return
	}
	res, err := h.geocoder.SearchCity(r.Context(), req.Name)
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
		"boundary_geojson": res.BoundaryGeoJSON,
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

// @Summary      Autocomplete city name (admin)
// @Description  Returns up to 5 Nominatim suggestions for a partial city name. Requires at least 3 characters.
// @Tags         cities
// @Produce      json
// @Security     BearerAuth
// @Param        q  query  string  true  "Partial city name (min 3 chars)"
// @Success      200  {object}  []autocompleteResult  "city suggestions"
// @Router       /admin/cities/autocomplete [get]
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

// @Summary      Create city (admin)
// @Description  Geocodes a city name, checks for duplicate slugs, and creates an active service area.
// @Tags         cities
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CityNameRequest  true  "City name"
// @Success      201  {object}  map[string]any  "created city"
// @Failure      400  {object}  ErrorResponse  "invalid request"
// @Failure      409  {object}  ErrorResponse  "city with this slug already exists"
// @Router       /admin/cities [post]
func (h *CityHandler) Create(w http.ResponseWriter, r *http.Request) {
	req, ok := h.decodeCityRequest(w, r)
	if !ok {
		return
	}
	res, err := h.geocoder.SearchCity(r.Context(), req.Name)
	if err != nil {
		h.writeGeocodeError(w, err)
		return
	}

	exists, err := h.repo.ExistsBySlug(r.Context(), res.Slug)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if exists {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "city with this slug already exists", "slug": res.Slug})
		return
	}

	dup, err := h.repo.ExistsByName(r.Context(), req.Name)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if dup {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "city with this name already exists", "name": req.Name})
		return
	}

	area := servicearea.ServiceArea{
		ID:             h.idGen.NewID(),
		Name:           req.Name,
		Slug:           res.Slug,
		CenterLat:      res.CenterLat,
		CenterLng:      res.CenterLng,
		RadiusKM:       25,
		PrimaryRadiusKM: req.PrimaryRadiusKM,
		BoundaryBufferKM: req.BoundaryBufferKM,
		IsActive:       true,
	}

	// Store a real administrative boundary when Nominatim gave us a trustworthy
	// polygon (a relation geometry). Suspicious results (non-relation, or
	// clearly an over-broad admin_level like a district) are NOT stored so the
	// area falls back to its circle and an admin can review before finalizing.
	var warnings []string
	area.BoundaryGeoJSON, warnings = suspectBoundary(res)

	area.ComputeBBox()
	if err := h.repo.Create(r.Context(), area); err != nil {
		writeInternalError(w, err)
		return
	}
	resp := map[string]any{"city": cityResponse(area)}
	if len(warnings) > 0 {
		resp["warnings"] = warnings
	}
	writeJSON(w, http.StatusCreated, resp)
}

// suspectBoundary decides whether to trust the boundary returned by the
// geocoder. It returns the polygon to persist (empty string to fall back to the
// circle) plus any warnings for the admin UI. A boundary is only trusted when
// it is an OSM relation and parses as a polygon/multipolygon geometry.
func suspectBoundary(res *geocoding.CitySearchResult) (string, []string) {
	var warnings []string
	boundary := res.BoundaryGeoJSON
	if boundary == "" {
		warnings = append(warnings, "Точная граница не найдена, используется круговая зона")
		return "", warnings
	}
	if res.OSMType != "relation" {
		warnings = append(warnings, "Граница получена не как relation административной границы (osm_type="+res.OSMType+"), автоматическое сохранение полигона отменено — круговая зона")
		return "", warnings
	}
	if !looksLikePolygonGeometry(boundary) {
		warnings = append(warnings, "Геометрия границы не распознана как полигон, используется круговая зона")
		return "", warnings
	}
	return boundary, warnings
}

// @Summary      List cities (admin)
// @Description  Returns all service areas (cities), both active and inactive.
// @Tags         cities
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of cities"
// @Router       /admin/cities [get]
func (h *CityHandler) List(w http.ResponseWriter, r *http.Request) {
	areas, err := h.repo.List(r.Context())
	if err != nil {
		writeInternalError(w, err)
		return
	}
	cities := make([]map[string]any, 0, len(areas))
	for _, a := range areas {
		cities = append(cities, cityResponse(a))
	}
	writeJSON(w, http.StatusOK, map[string]any{"cities": cities})
}

type cityPatchRequest struct {
	IsActive          *bool    `json:"is_active"`
	PrimaryRadiusKM   *float64 `json:"primary_radius_km"`
	RadiusKM          *float64 `json:"radius_km"`
	BoundaryBufferKM  *float64 `json:"boundary_buffer_km"`
}

// @Summary      Update city (admin)
// @Description  Updates a service area (city): toggles active status and/or adjusts primary_radius_km (km from city center where orders are accepted).
// @Tags         cities
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  string  true  "City ID"
// @Success      200  {object}  map[string]any  "updated city"
// @Failure      400  {object}  ErrorResponse  "invalid request"
// @Failure      404  {object}  ErrorResponse  "city not found"
// @Router       /admin/cities/{id} [patch]
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

	if req.IsActive != nil {
		if err := h.repo.SetActive(r.Context(), id, *req.IsActive); err != nil {
			if errors.Is(err, servicearea.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found"})
				return
			}
			writeInternalError(w, err)
			return
		}
	}

	if req.PrimaryRadiusKM != nil || req.RadiusKM != nil || req.BoundaryBufferKM != nil {
		area, err := h.repo.GetByID(r.Context(), id)
		if err != nil {
			if errors.Is(err, servicearea.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found"})
				return
			}
			writeInternalError(w, err)
			return
		}
		if req.PrimaryRadiusKM != nil {
			area.PrimaryRadiusKM = *req.PrimaryRadiusKM
		}
		if req.RadiusKM != nil {
			area.RadiusKM = *req.RadiusKM
		}
		if req.BoundaryBufferKM != nil {
			area.BoundaryBufferKM = *req.BoundaryBufferKM
		}
		area.ComputeBBox()
		if err := h.repo.Update(r.Context(), *area); err != nil {
			writeInternalError(w, err)
			return
		}
	}

	updated, err := h.repo.GetByID(r.Context(), id)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"city": cityResponse(*updated)})
}

// @Summary      Delete city (admin)
// @Description  Hard-deletes a service area. Fails if there are active orders in this city or any order references the city.
// @Tags         cities
// @Produce      json
// @Security     BearerAuth
// @Param        id  path  string  true  "City ID"
// @Success      200  {object}  map[string]any  "deleted confirmation"
// @Failure      400  {object}  ErrorResponse  "invalid request"
// @Failure      404  {object}  ErrorResponse  "city not found"
// @Failure      409  {object}  ErrorResponse  "city is in use or has active orders"
// @Router       /admin/cities/{id} [delete]
func (h *CityHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id is required"})
		return
	}
	if err := h.repo.Delete(r.Context(), id); err != nil {
		switch {
		case errors.Is(err, servicearea.ErrAreaInUse):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "Cannot delete: city is in use and cannot be deleted"})
		case errors.Is(err, servicearea.ErrNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found"})
		default:
			writeInternalError(w, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

// decodeName parses and validates a { "name": "..." } body.
func (h *CityHandler) decodeCityRequest(w http.ResponseWriter, r *http.Request) (cityNameRequest, bool) {
	var req cityNameRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return cityNameRequest{}, false
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
		return cityNameRequest{}, false
	}
	if req.PrimaryRadiusKM <= 0 {
		req.PrimaryRadiusKM = 50
	}
	if req.BoundaryBufferKM <= 0 {
		req.BoundaryBufferKM = 7
	}
	return req, true
}

// writeGeocodeError maps geocoding failures to client-facing statuses.
func looksLikePolygonGeometry(geoJSON string) bool {
	var raw struct {
		Type     string          `json:"type"`
		Geometry json.RawMessage `json:"geometry"`
	}
	if err := json.Unmarshal([]byte(geoJSON), &raw); err != nil {
		return false
	}
	t := raw.Type
	if t == "Feature" || t == "FeatureCollection" {
		return strings.Contains(geoJSON, `"Polygon"`) || strings.Contains(geoJSON, `"MultiPolygon"`)
	}
	return t == "Polygon" || t == "MultiPolygon"
}

func (h *CityHandler) writeGeocodeError(w http.ResponseWriter, err error) {
	if errors.Is(err, geocoding.ErrCityNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found by geocoder"})
		return
	}
	writeUpstreamError(w, http.StatusBadGateway, err)
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
		"center": centerPayload{
			Lat: a.CenterLat,
			Lng: a.CenterLng,
		},
		"radius_km":          a.RadiusKM,
		"primary_radius_km":  a.PrimaryRadiusKM,
		"boundary_buffer_km": a.BoundaryBufferKM,
		"boundary_geojson":   a.BoundaryGeoJSON,
		"is_active":          a.IsActive,
	}
}
