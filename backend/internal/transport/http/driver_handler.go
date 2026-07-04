package http

import (
	"context"
	"encoding/json"
	"errors"
	"log"
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
	GetProfileByID(ctx context.Context, id string) (*driverdomain.DriverProfile, error)
}

type DriverLocationRepository interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
}

type DriverProfileRepository interface {
	UpsertTaxProfile(ctx context.Context, profile *userdomain.TaxProfile) error
	GetTaxProfile(ctx context.Context, driverID string) (*userdomain.TaxProfile, error)
}

type DriverVerificationRepository interface {
	GetVerificationStatus(ctx context.Context, driverID string) (*DriverVerificationStatus, error)
}

type ActiveOrderChecker interface {
	HasActiveOrderWithDriver(ctx context.Context, clientID, driverID string) (bool, error)
}

type DriverVerificationStatus struct {
	DriverID         string                      `json:"driver_id"`
	Status           string                      `json:"status"` // "pending", "approved", "rejected", "changes_requested", "blocked"
	DocumentsUploaded map[string]DocumentInfo    `json:"documents_uploaded"`
	SubmittedAt      *time.Time                  `json:"submitted_at"`
	UpdatedAt        *time.Time                  `json:"updated_at"`
	AdminComments    string                      `json:"admin_comments,omitempty"`
}

type DocumentInfo struct {
	URL         string `json:"url"`
	UploadedAt  time.Time `json:"uploaded_at"`
	ContentType string `json:"content_type"`
}

type DriverHandler struct {
	setStatusUC       *driveruc.SetStatusUseCase
	driverRepo        DriverRepository
	locationRepo      DriverLocationRepository
	profileRepo       DriverProfileRepository
	verificationRepo  DriverVerificationRepository
	orderChecker      ActiveOrderChecker
	gates             *driveruc.GateService
	npd               *driveruc.NPDService
	clock             interface{ Now() time.Time }
	allowMockLocation bool
	isProduction      bool
	debugMode         bool
}

func NewDriverHandler(
	setStatusUC *driveruc.SetStatusUseCase,
	driverRepo DriverRepository,
	locationRepo DriverLocationRepository,
	profileRepo DriverProfileRepository,
	verificationRepo DriverVerificationRepository,
	orderChecker ActiveOrderChecker,
	gates *driveruc.GateService,
	npd *driveruc.NPDService,
	clock interface{ Now() time.Time },
	allowMockLocation bool,
	isProduction bool,
	debugMode bool,
) *DriverHandler {
	return &DriverHandler{
		setStatusUC:       setStatusUC,
		driverRepo:        driverRepo,
		locationRepo:      locationRepo,
		profileRepo:       profileRepo,
		verificationRepo:  verificationRepo,
		orderChecker:      orderChecker,
		gates:             gates,
		npd:               npd,
		clock:             clock,
		allowMockLocation: allowMockLocation,
		isProduction:      isProduction,
		debugMode:         debugMode,
	}
}

type setDriverStatusRequest struct {
	Status   string                    `json:"status"`
	Lat      *float64                  `json:"lat"`
	Lng      *float64                  `json:"lng"`
	Location *setDriverLocationRequest `json:"location"`
}

type setDriverLocationRequest struct {
	Lat    *float64 `json:"lat"`
	Lng    *float64 `json:"lng"`
	IsMock bool     `json:"is_mock"`
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

type driverProfileResponse struct {
	ID             string  `json:"id"`
	UserID         string  `json:"user_id"`
	Status         string  `json:"status"`
	CurrentOrderID *string `json:"current_order_id"`
	LastSeenAt     string  `json:"last_seen_at"`
	UpdatedAt      string  `json:"updated_at"`
	FullName       string  `json:"full_name"`
	Phone          string  `json:"phone"`
	VehiclePlate   string  `json:"vehicle_plate"`
	VehicleModel   string  `json:"vehicle_model"`
	VehicleType    string  `json:"vehicle_type"`
	RatingAverage  float64 `json:"rating_average"`
	RatingCount    int     `json:"rating_count"`
	TotalOrders    int     `json:"total_orders"`
	AvatarURL      *string `json:"avatar_url,omitempty"`
}

type locationResponse struct {
	Lat       float64 `json:"lat"`
	Lng       float64 `json:"lng"`
	UpdatedAt string  `json:"updated_at"`
}

// canAccessDriver returns true if the caller is allowed to see the target
// driver's status/location. Admins see all; drivers see themselves; clients
// see only a driver they have an active order with.
func (h *DriverHandler) canAccessDriver(ctx context.Context, callerID string, callerRole auth.Role, targetDriverID string) bool {
	if callerRole == auth.RoleAdmin {
		return true
	}
	if callerRole == auth.RoleDriver && callerID == targetDriverID {
		return true
	}
	if callerRole == auth.RoleClient && h.orderChecker != nil {
		ok, err := h.orderChecker.HasActiveOrderWithDriver(ctx, callerID, targetDriverID)
		if err == nil && ok {
			return true
		}
	}
	return false
}

// @Summary      Get driver
// @Description  Returns a driver's basic info. Access control: admins see all, drivers see themselves, clients see drivers they have an active order with.
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "driver info"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "driver not found"
// @Router       /drivers/{driverID} [get]
func (h *DriverHandler) GetDriver(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	callerID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	callerRole, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.canAccessDriver(r.Context(), callerID, callerRole, driverID) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	drv, err := h.driverRepo.GetByID(r.Context(), driverID)
	if err != nil {
		h.writeDriverError(w, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"driver": newDriverResponse(drv)})
}

// @Summary      Get driver profile
// @Description  Returns the full driver profile including name, phone, vehicle info, and ratings.
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "driver profile"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "driver not found"
// @Router       /drivers/{driverID}/profile [get]
func (h *DriverHandler) GetDriverProfile(w http.ResponseWriter, r *http.Request) {
	driverID, ok := h.authorizeDriverScope(w, r)
	if !ok {
		return
	}

	profile, err := h.driverRepo.GetProfileByID(r.Context(), driverID)
	if err != nil {
		h.writeDriverError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"profile": newDriverProfileResponse(profile)})
}

// @Summary      Set driver status
// @Description  Changes the driver's online/offline status. Going online requires passing driver gates (docs, tax, subscription).
// @Tags         drivers
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string                   true  "Driver ID"
// @Param        body      body  SetDriverStatusRequest   true  "Status and optional location"
// @Success      200  {object}  map[string]any  "updated driver"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden or gate check failed"
// @Router       /drivers/{driverID}/status [post]
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
	var isMock bool
	if req.Location != nil {
		lat = req.Location.Lat
		lng = req.Location.Lng
		isMock = req.Location.IsMock
	}
	if isMock && h.isProduction {
		log.Printf("SECURITY WARN: driver %s sent mock location", driverID)
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

// @Summary      Upsert tax profile
// @Description  Creates or updates the driver's tax profile (INN and taxpayer type). Admin updates are auto-verified.
// @Tags         drivers
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string               true  "Driver ID"
// @Param        body      body  TaxProfileRequest     true  "Tax profile payload"
// @Success      200  {object}  map[string]any  "tax profile"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Router       /drivers/{driverID}/tax-profile [put]
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

// @Summary      Get verification status
// @Description  Returns the driver's document verification status, uploaded documents, and moderation state.
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "verification status with documents"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Router       /drivers/{driverID}/verification-status [get]
func (h *DriverHandler) GetVerificationStatus(w http.ResponseWriter, r *http.Request) {
	driverID, ok := h.authorizeDriverScope(w, r)
	if !ok {
		return
	}

	if h.verificationRepo == nil {
		h.writeJSON(w, http.StatusOK, map[string]any{
			"driver_id": driverID,
			"status":    "not_submitted",
			"documents_uploaded": map[string]any{},
		})
		return
	}

	status, err := h.verificationRepo.GetVerificationStatus(r.Context(), driverID)
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}

	if status == nil {
		h.writeJSON(w, http.StatusOK, map[string]any{
			"driver_id": driverID,
			"status":    "not_submitted",
			"documents_uploaded": map[string]any{},
		})
		return
	}

	h.writeJSON(w, http.StatusOK, status)
}

// @Summary      Get tax profile
// @Description  Returns the driver's tax profile (INN, taxpayer type, verification status).
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "tax profile"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "tax profile not found"
// @Router       /drivers/{driverID}/tax-profile [get]
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

// @Summary      Get driver location
// @Description  Returns the driver's last known location. Access control mirrors GetDriver.
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "location with lat/lng/updated_at"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "location not found"
// @Router       /drivers/{driverID}/location [get]
func (h *DriverHandler) GetLocation(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	callerID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	callerRole, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.canAccessDriver(r.Context(), callerID, callerRole, driverID) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
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

func newDriverProfileResponse(profile *driverdomain.DriverProfile) driverProfileResponse {
	return driverProfileResponse{
		ID:             profile.ID,
		UserID:         profile.UserID,
		Status:         string(profile.Status),
		CurrentOrderID: profile.CurrentOrderID,
		LastSeenAt:     profile.LastSeenAt.Format("2006-01-02T15:04:05.000Z07:00"),
		UpdatedAt:      profile.UpdatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		FullName:       profile.FullName,
		Phone:          profile.Phone,
		VehiclePlate:   profile.VehiclePlate,
		VehicleModel:   profile.VehicleModel,
		VehicleType:    profile.VehicleType,
		RatingAverage:  profile.RatingAverage,
		RatingCount:    profile.RatingCount,
		TotalOrders:    profile.TotalOrders,
		AvatarURL:      profile.AvatarURL,
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
	status := profile.NPDConnectionStatus
	if status == "" {
		status = userdomain.NPDStatusNotConnected
	}
	out := map[string]any{
		"driver_id":             profile.DriverID,
		"inn":                   profile.INN,
		"taxpayer_type":         profile.TaxpayerType,
		"verification_status":   profile.VerificationStatus,
		"npd_connection_status": status,
		"created_at":            profile.CreatedAt.Format(time.RFC3339),
		"updated_at":            profile.UpdatedAt.Format(time.RFC3339),
	}
	if profile.NPDConnectedAt != nil {
		out["npd_connected_at"] = profile.NPDConnectedAt.Format(time.RFC3339)
	}
	if profile.NPDRevokedAt != nil {
		out["npd_revoked_at"] = profile.NPDRevokedAt.Format(time.RFC3339)
	}
	return out
}

type npdConnectRequest struct {
	INN string `json:"inn"`
}

// @Summary      Get NPD status
// @Description  Returns the driver's Moy Nalog (FNS NPD/self-employment) connection status.
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "NPD status with connection state"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Router       /drivers/{driverID}/npd/status [get]
func (h *DriverHandler) GetNPDStatus(w http.ResponseWriter, r *http.Request) {
	driverID, ok := h.authorizeDriverScope(w, r)
	if !ok {
		return
	}
	profile, err := h.npd.Status(r.Context(), driverID)
	if err != nil {
		if errors.Is(err, userdomain.ErrTaxProfileNotFound) {
			h.writeJSON(w, http.StatusOK, map[string]any{
				"driver_id":             driverID,
				"npd_connection_status": userdomain.NPDStatusNotConnected,
				"inn":                   "",
			})
			return
		}
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"profile": taxProfileJSON(profile)})
}

// @Summary      Connect NPD
// @Description  Connects the driver to Moy Nalog (FNS) via INN for self-employment tax verification.
// @Tags         drivers
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string              true  "Driver ID"
// @Param        body      body  NPDConnectRequest   true  "INN payload"
// @Success      200  {object}  map[string]any  "updated tax profile"
// @Failure      400  {object}  ErrorResponse  "INN required"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      503  {object}  ErrorResponse  "NPD not configured"
// @Router       /drivers/{driverID}/npd/connect [post]
func (h *DriverHandler) ConnectNPD(w http.ResponseWriter, r *http.Request) {
	driverID, ok := h.authorizeDriverScope(w, r)
	if !ok {
		return
	}
	var req npdConnectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}
	profile, err := h.npd.Connect(r.Context(), driverID, req.INN)
	if err != nil {
		switch {
		case errors.Is(err, driveruc.ErrINNRequired):
			h.writeError(w, http.StatusBadRequest, err)
		case errors.Is(err, userdomain.ErrNPDProviderNotConfigured):
			h.writeJSON(w, http.StatusServiceUnavailable, map[string]any{
				"error":   "npd_not_configured",
				"message": "Интеграция с «Мой Налог» появится после получения статуса партнёра ФНС.",
			})
		case errors.Is(err, userdomain.ErrTaxProfileNotFound):
			h.writeError(w, http.StatusNotFound, err)
		default:
			h.writeError(w, http.StatusInternalServerError, err)
		}
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"profile": taxProfileJSON(profile)})
}

// @Summary      Disconnect NPD
// @Description  Revokes the NPD (Moy Nalog) connection for the driver. Only local tokens are removed.
// @Tags         drivers
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  EmptyResponse
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "tax profile not found"
// @Router       /drivers/{driverID}/npd/disconnect [post]
func (h *DriverHandler) DisconnectNPD(w http.ResponseWriter, r *http.Request) {
	driverID, ok := h.authorizeDriverScope(w, r)
	if !ok {
		return
	}
	if err := h.npd.Disconnect(r.Context(), driverID); err != nil {
		if errors.Is(err, userdomain.ErrTaxProfileNotFound) {
			h.writeError(w, http.StatusNotFound, err)
			return
		}
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// authorizeDriverScope enforces that the caller is either the driver
// themselves or an admin. Writes the appropriate 401/403 error and
// returns ok=false if denied — callers should return immediately.
func (h *DriverHandler) authorizeDriverScope(w http.ResponseWriter, r *http.Request) (string, bool) {
	driverID := chi.URLParam(r, "driverID")
	if h.debugMode {
		return driverID, true
	}
	authUserID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return "", false
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return "", false
	}
	if role != auth.RoleAdmin && driverID != authUserID {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return "", false
	}
	return driverID, true
}
