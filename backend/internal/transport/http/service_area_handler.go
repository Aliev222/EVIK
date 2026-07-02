package http

import (
	"net/http"
	"strconv"

	servicearea "evik/backend/internal/domain/servicearea"
)

type ServiceAreaHandler struct {
	repo servicearea.Repository
}

func NewServiceAreaHandler(repo servicearea.Repository) *ServiceAreaHandler {
	return &ServiceAreaHandler{repo: repo}
}

// @Summary      Check service area
// @Description  Checks whether the given coordinates are inside an active service area.
// @Tags         service-areas
// @Produce      json
// @Param        lat  query  number  true  "Latitude"
// @Param        lng  query  number  true  "Longitude"
// @Success      200  {object}  map[string]any  "allowed status with optional service area"
// @Failure      400  {object}  ErrorResponse  "lat/lng required"
// @Router       /service-areas/check [get]
func (h *ServiceAreaHandler) Check(w http.ResponseWriter, r *http.Request) {
	lat, err := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "lat is required"})
		return
	}
	lng, err := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "lng is required"})
		return
	}
	area, ok, err := h.repo.CheckPoint(r.Context(), lat, lng)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	payload := map[string]any{"allowed": ok}
	if area != nil {
		payload["service_area"] = map[string]any{
			"id":   area.ID,
			"name": area.Name,
		}
	}
	writeJSON(w, http.StatusOK, payload)
}
