package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	driveruc "evik/backend/internal/usecase/driver"
	"github.com/go-chi/chi/v5"
)

type DriverRepository interface {
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
}

type DriverLocationRepository interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
}

type DriverHandler struct {
	setStatusUC  *driveruc.SetStatusUseCase
	driverRepo   DriverRepository
	locationRepo DriverLocationRepository
}

func NewDriverHandler(
	setStatusUC *driveruc.SetStatusUseCase,
	driverRepo DriverRepository,
	locationRepo DriverLocationRepository,
) *DriverHandler {
	return &DriverHandler{
		setStatusUC:  setStatusUC,
		driverRepo:   driverRepo,
		locationRepo: locationRepo,
	}
}

type setDriverStatusRequest struct {
	UserID string   `json:"user_id"`
	Status string   `json:"status"`
	Lat    *float64 `json:"lat"`
	Lng    *float64 `json:"lng"`
}

type driverResponse struct {
	ID             string  `json:"id"`
	UserID         string  `json:"user_id"`
	Status         string  `json:"status"`
	CurrentOrderID *string `json:"current_order_id"`
	LastSeenAt     string  `json:"last_seen_at"`
	UpdatedAt      string  `json:"updated_at"`
}

type locationResponse struct {
	Lat       float64 `json:"lat"`
	Lng       float64 `json:"lng"`
	UpdatedAt string  `json:"updated_at"`
}

func (h *DriverHandler) GetDriver(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	drv, err := h.driverRepo.GetByID(r.Context(), driverID)
	if err != nil {
		h.writeDriverError(w, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"driver": newDriverResponse(drv)})
}

func (h *DriverHandler) SetStatus(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	var req setDriverStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}

	drv, err := h.setStatusUC.Execute(r.Context(), driveruc.SetStatusInput{
		DriverID: driverID,
		UserID:   req.UserID,
		Status:   driverdomain.Status(req.Status),
		Lat:      req.Lat,
		Lng:      req.Lng,
	})
	if err != nil {
		h.writeDriverError(w, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"driver": newDriverResponse(drv)})
}

func (h *DriverHandler) GetLocation(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	loc, err := h.locationRepo.GetLastLocation(r.Context(), driverID)
	if err != nil {
		h.writeDriverError(w, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{
		"location": locationResponse{
			Lat:       loc.Lat,
			Lng:       loc.Lng,
			UpdatedAt: loc.UpdatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		},
	})
}

func (h *DriverHandler) writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func (h *DriverHandler) writeError(w http.ResponseWriter, status int, err error) {
	h.writeJSON(w, status, map[string]string{"error": err.Error()})
}

func (h *DriverHandler) writeDriverError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, driverdomain.ErrValidationFailed):
		h.writeError(w, http.StatusBadRequest, err)
	case errors.Is(err, driverdomain.ErrDriverNotFound):
		h.writeError(w, http.StatusNotFound, err)
	case errors.Is(err, driverdomain.ErrDriverUnavailable):
		h.writeError(w, http.StatusConflict, err)
	case errors.Is(err, locationdomain.ErrLocationNotFound):
		h.writeError(w, http.StatusNotFound, err)
	default:
		h.writeError(w, http.StatusInternalServerError, err)
	}
}

func newDriverResponse(drv *driverdomain.Driver) driverResponse {
	return driverResponse{
		ID:             drv.ID,
		UserID:         drv.UserID,
		Status:         string(drv.Status),
		CurrentOrderID: drv.CurrentOrderID,
		LastSeenAt:     drv.LastSeenAt.Format("2006-01-02T15:04:05.000Z07:00"),
		UpdatedAt:      drv.UpdatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
	}
}
