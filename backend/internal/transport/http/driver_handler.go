package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"evik/backend/internal/auth"
	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	userdomain "evik/backend/internal/domain/user"
	driveruc "evik/backend/internal/usecase/driver"
	"github.com/go-chi/chi/v5"
)

type DriverRepository interface {
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
}

type DriverLocationRepository interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
}

type DriverProfileRepository interface {
	UpsertTaxProfile(ctx context.Context, profile *userdomain.TaxProfile) error
	GetTaxProfile(ctx context.Context, driverID string) (*userdomain.TaxProfile, error)
}

type DriverHandler struct {
	setStatusUC  *driveruc.SetStatusUseCase
	driverRepo   DriverRepository
	locationRepo DriverLocationRepository
	profileRepo  DriverProfileRepository
	gates        *driveruc.GateService
	clock        interface{ Now() time.Time }
}

func NewDriverHandler(
	setStatusUC *driveruc.SetStatusUseCase,
	driverRepo DriverRepository,
	locationRepo DriverLocationRepository,
	profileRepo DriverProfileRepository,
	gates *driveruc.GateService,
	clock interface{ Now() time.Time },
) *DriverHandler {
	return &DriverHandler{
		setStatusUC:  setStatusUC,
		driverRepo:   driverRepo,
		locationRepo: locationRepo,
		profileRepo:  profileRepo,
		gates:        gates,
		clock:        clock,
	}
}

type setDriverStatusRequest struct {
	Status   string                    `json:"status"`
	Lat      *float64                  `json:"lat"`
	Lng      *float64                  `json:"lng"`
	Location *setDriverLocationRequest `json:"location"`
}

type setDriverLocationRequest struct {
	Lat *float64 `json:"lat"`
	Lng *float64 `json:"lng"`
}

type taxProfileRequest struct {
	INN          string `json:"inn"`
	TaxpayerType string `json:"taxpayer_type"`
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
	authUserID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if role != auth.RoleAdmin && driverID != authUserID {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	if req.Status == string(driverdomain.StatusOnline) && role != auth.RoleAdmin && h.gates != nil {
		if err := h.gates.EnsureCanWork(r.Context(), driverID); err != nil {
			h.writeDriverGateError(w, err)
			return
		}
	}
	lat, lng := req.Lat, req.Lng
	if req.Location != nil {
		lat = req.Location.Lat
		lng = req.Location.Lng
	}

	drv, err := h.setStatusUC.Execute(r.Context(), driveruc.SetStatusInput{
		DriverID: driverID,
		UserID:   authUserID,
		Status:   driverdomain.Status(req.Status),
		Lat:      lat,
		Lng:      lng,
	})
	if err != nil {
		h.writeDriverError(w, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"driver": newDriverResponse(drv)})
}

func (h *DriverHandler) UpsertTaxProfile(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	authUserID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if role != auth.RoleAdmin && driverID != authUserID {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	var req taxProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}
	if !validINN(req.INN) || (req.TaxpayerType != "self_employed" && req.TaxpayerType != "ip") {
		h.writeError(w, http.StatusBadRequest, errors.New("valid inn and taxpayer_type self_employed/ip are required"))
		return
	}
	now := h.clock.Now()
	status := "pending"
	if role == auth.RoleAdmin {
		status = "verified"
	}
	profile := &userdomain.TaxProfile{
		DriverID:           driverID,
		INN:                req.INN,
		TaxpayerType:       req.TaxpayerType,
		VerificationStatus: status,
		CreatedAt:          now,
		UpdatedAt:          now,
	}
	if err := h.profileRepo.UpsertTaxProfile(r.Context(), profile); err != nil {
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"tax_profile": taxProfileJSON(profile)})
}

func (h *DriverHandler) GetTaxProfile(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	authUserID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if role != auth.RoleAdmin && driverID != authUserID {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	profile, err := h.profileRepo.GetTaxProfile(r.Context(), driverID)
	if err != nil {
		if errors.Is(err, userdomain.ErrTaxProfileNotFound) {
			h.writeError(w, http.StatusNotFound, err)
			return
		}
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"tax_profile": taxProfileJSON(profile)})
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

func (h *DriverHandler) writeDriverGateError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, driveruc.ErrDriverDocumentsNotApproved),
		errors.Is(err, driveruc.ErrDriverTaxNotVerified),
		errors.Is(err, driveruc.ErrDriverSubscriptionInactive):
		h.writeError(w, http.StatusForbidden, err)
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

func validINN(value string) bool {
	if len(value) != 10 && len(value) != 12 {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func taxProfileJSON(profile *userdomain.TaxProfile) map[string]any {
	return map[string]any{
		"driver_id":           profile.DriverID,
		"inn":                 profile.INN,
		"taxpayer_type":       profile.TaxpayerType,
		"verification_status": profile.VerificationStatus,
		"created_at":          profile.CreatedAt.Format(time.RFC3339),
		"updated_at":          profile.UpdatedAt.Format(time.RFC3339),
	}
}
