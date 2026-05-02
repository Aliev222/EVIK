package http

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	admindomain "evik/backend/internal/domain/admin"
	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	"github.com/go-chi/chi/v5"
)

type AdminRepository interface {
	Overview(ctx context.Context) (admindomain.Overview, error)
	ListDriverVerifications(ctx context.Context, limit int) ([]admindomain.DriverVerification, error)
	UpsertDriverVerification(ctx context.Context, item admindomain.DriverVerification) error
	DecideDriverVerification(ctx context.Context, id string, status string, reason string, moderatorID string, auditID string, now time.Time) error
	ListUsers(ctx context.Context, limit int) ([]admindomain.User, error)
	ListReviews(ctx context.Context, limit int) ([]admindomain.Review, error)
	CreateReview(ctx context.Context, item admindomain.Review) error
}

type AdminDriverRepository interface {
	ListActive(ctx context.Context, limit int) ([]*driverdomain.Driver, error)
}

type AdminLocationRepository interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
}

type AdminIDGenerator interface {
	NewID() string
}

type AdminClock interface {
	Now() time.Time
}

type DocumentStorageConfig struct {
	Endpoint  string
	Region    string
	Bucket    string
	AccessKey string
	SecretKey string
}

type AdminHandler struct {
	repo         AdminRepository
	driverRepo   AdminDriverRepository
	locationRepo AdminLocationRepository
	idGen        AdminIDGenerator
	clock        AdminClock
	storage      DocumentStorageConfig
}

func NewAdminHandler(
	repo AdminRepository,
	driverRepo AdminDriverRepository,
	locationRepo AdminLocationRepository,
	idGen AdminIDGenerator,
	clock AdminClock,
	storage DocumentStorageConfig,
) *AdminHandler {
	return &AdminHandler{
		repo:         repo,
		driverRepo:   driverRepo,
		locationRepo: locationRepo,
		idGen:        idGen,
		clock:        clock,
		storage:      storage,
	}
}

type adminDecisionRequest struct {
	Reason string `json:"reason"`
}

type submitDriverVerificationRequest struct {
	UserID       string   `json:"user_id"`
	FullName     string   `json:"full_name"`
	Phone        string   `json:"phone"`
	City         string   `json:"city"`
	VehicleModel string   `json:"vehicle_model"`
	VehiclePlate string   `json:"vehicle_plate"`
	VehicleType  string   `json:"vehicle_type"`
	Documents    []string `json:"documents"`
	Signals      []string `json:"signals"`
}

type createDriverReviewRequest struct {
	OrderID  string `json:"order_id"`
	DriverID string `json:"driver_id"`
	Stars    int    `json:"stars"`
	Text     string `json:"text"`
}

type documentUploadRequest struct {
	FileName    string `json:"file_name"`
	ContentType string `json:"content_type"`
}

type adminDriverLocationResponse struct {
	ID       string  `json:"id"`
	Name     string  `json:"name"`
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	Status   string  `json:"status"`
	Stars    float64 `json:"stars"`
	Vehicle  string  `json:"vehicle"`
	LastSeen string  `json:"last_seen"`
}

func (h *AdminHandler) Overview(w http.ResponseWriter, r *http.Request) {
	overview, err := h.repo.Overview(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"total_users":          overview.TotalUsers,
		"clients":              overview.Clients,
		"drivers":              overview.Drivers,
		"online_drivers":       overview.OnlineDrivers,
		"pending_moderations":  overview.PendingModerations,
		"average_driver_stars": overview.AverageDriverStars,
		"reviews_today":        overview.ReviewsToday,
		"active_orders":        overview.ActiveOrders,
	})
}

func (h *AdminHandler) ListDriverVerifications(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.ListDriverVerifications(r.Context(), parseAdminLimit(r, 50, 100))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]map[string]any, 0, len(items))
	for _, item := range items {
		payload = append(payload, map[string]any{
			"id":              item.ID,
			"driver_name":     item.DriverName,
			"phone":           item.Phone,
			"city":            item.City,
			"vehicle":         item.Vehicle,
			"plate":           item.Plate,
			"vehicle_type":    item.VehicleType,
			"status":          item.Status,
			"risk":            item.Risk,
			"stars":           item.Stars,
			"orders":          item.Orders,
			"submitted_at":    item.SubmittedAt.Format(time.RFC3339),
			"documents":       item.Documents,
			"signals":         item.Signals,
			"decision_reason": item.DecisionReason,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": payload})
}

func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.ListUsers(r.Context(), parseAdminLimit(r, 100, 200))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]map[string]any, 0, len(items))
	for _, item := range items {
		payload = append(payload, map[string]any{
			"id":     item.ID,
			"name":   item.Name,
			"role":   item.Role,
			"phone":  item.Phone,
			"orders": item.Orders,
			"status": item.Status,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": payload})
}

func (h *AdminHandler) ListReviews(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.ListReviews(r.Context(), parseAdminLimit(r, 50, 100))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]map[string]any, 0, len(items))
	for _, item := range items {
		payload = append(payload, map[string]any{
			"id":          item.ID,
			"order_id":    item.OrderID,
			"driver_id":   item.DriverID,
			"driver_name": item.DriverName,
			"client_id":   item.ClientID,
			"client_name": item.ClientName,
			"stars":       item.Stars,
			"text":        item.Text,
			"created_at":  item.CreatedAt.Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": payload})
}

func (h *AdminHandler) SubmitDriverVerification(w http.ResponseWriter, r *http.Request) {
	var req submitDriverVerificationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
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

	userID := authUserID
	if roleFromRequest := strings.TrimSpace(req.UserID); role == "admin" && roleFromRequest != "" {
		userID = roleFromRequest
	}

	fullName := strings.TrimSpace(req.FullName)
	vehicleModel := strings.TrimSpace(req.VehicleModel)
	vehiclePlate := strings.ToUpper(strings.TrimSpace(req.VehiclePlate))
	vehicleType := strings.TrimSpace(req.VehicleType)
	if fullName == "" || vehicleModel == "" || vehiclePlate == "" || vehicleType == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "full_name, vehicle_model, vehicle_plate and vehicle_type are required"})
		return
	}
	if len(req.Documents) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "at least one document is required"})
		return
	}

	now := h.clock.Now()
	item := admindomain.DriverVerification{
		ID:          userID,
		UserID:      userID,
		DriverName:  fullName,
		Phone:       strings.TrimSpace(req.Phone),
		City:        strings.TrimSpace(req.City),
		Vehicle:     vehicleModel,
		Plate:       vehiclePlate,
		VehicleType: vehicleType,
		Status:      "pending",
		Risk:        "low",
		SubmittedAt: now,
		Documents:   sanitizeStringList(req.Documents, 20),
		Signals:     sanitizeStringList(req.Signals, 20),
	}
	if err := h.repo.UpsertDriverVerification(r.Context(), item); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"verification": map[string]any{
			"id":           item.ID,
			"user_id":      item.UserID,
			"status":       item.Status,
			"submitted_at": item.SubmittedAt.Format(time.RFC3339),
		},
	})
}

func (h *AdminHandler) CreateReview(w http.ResponseWriter, r *http.Request) {
	var req createDriverReviewRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	clientID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	orderID := strings.TrimSpace(req.OrderID)
	driverID := strings.TrimSpace(req.DriverID)
	text := strings.TrimSpace(req.Text)
	if orderID == "" || driverID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "order_id and driver_id are required"})
		return
	}
	if req.Stars < 1 || req.Stars > 5 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "stars must be from 1 to 5"})
		return
	}
	if len(text) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "review text is too long"})
		return
	}

	item := admindomain.Review{
		ID:        h.idGen.NewID(),
		OrderID:   orderID,
		DriverID:  driverID,
		ClientID:  clientID,
		Stars:     req.Stars,
		Text:      text,
		CreatedAt: h.clock.Now(),
	}
	if err := h.repo.CreateReview(r.Context(), item); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"review": map[string]any{
			"id":         item.ID,
			"order_id":   item.OrderID,
			"driver_id":  item.DriverID,
			"client_id":  item.ClientID,
			"stars":      item.Stars,
			"text":       item.Text,
			"created_at": item.CreatedAt.Format(time.RFC3339),
		},
	})
}

func (h *AdminHandler) CreateDocumentUpload(w http.ResponseWriter, r *http.Request) {
	if h.storage.Endpoint == "" || h.storage.Bucket == "" || h.storage.AccessKey == "" || h.storage.SecretKey == "" {
		writeJSON(w, http.StatusNotImplemented, map[string]string{"error": "document storage is not configured"})
		return
	}

	var req documentUploadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	fileName := strings.TrimSpace(req.FileName)
	contentType := strings.TrimSpace(req.ContentType)
	if fileName == "" || contentType == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "file_name and content_type are required"})
		return
	}

	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	objectKey := "driver-documents/" + userID + "/" + h.idGen.NewID() + "-" + sanitizeObjectName(fileName)
	writeJSON(w, http.StatusOK, map[string]any{
		"bucket":      h.storage.Bucket,
		"object_key":  objectKey,
		"public_url":  strings.TrimRight(h.storage.Endpoint, "/") + "/" + h.storage.Bucket + "/" + objectKey,
		"upload_mode": "server_presign_required",
		"message":     "S3 is configured. Add presigned PUT signing before uploading real files from mobile clients.",
	})
}

func (h *AdminHandler) ListOnlineDrivers(w http.ResponseWriter, r *http.Request) {
	drivers, err := h.driverRepo.ListActive(r.Context(), parseAdminLimit(r, 100, 200))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]adminDriverLocationResponse, 0, len(drivers))
	for _, driver := range drivers {
		loc, err := h.locationRepo.GetLastLocation(r.Context(), driver.ID)
		if err != nil {
			if errors.Is(err, locationdomain.ErrLocationNotFound) {
				continue
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		payload = append(payload, adminDriverLocationResponse{
			ID:       driver.ID,
			Name:     driver.UserID,
			Lat:      loc.Lat,
			Lng:      loc.Lng,
			Status:   string(driver.Status),
			Stars:    0,
			Vehicle:  "",
			LastSeen: loc.UpdatedAt.Format(time.RFC3339),
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{"items": payload})
}

func (h *AdminHandler) ApproveDriverVerification(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "approved", false)
}

func (h *AdminHandler) RejectDriverVerification(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "rejected", true)
}

func (h *AdminHandler) RequestDriverVerificationChanges(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "changes_requested", true)
}

func (h *AdminHandler) BlockDriverVerification(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "blocked", true)
}

func (h *AdminHandler) decideDriverVerification(w http.ResponseWriter, r *http.Request, status string, requireReason bool) {
	verificationID := strings.TrimSpace(chi.URLParam(r, "verificationID"))
	if verificationID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "verification id is required"})
		return
	}

	var req adminDecisionRequest
	if r.Body != nil {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
			return
		}
	}
	reason := strings.TrimSpace(req.Reason)
	if requireReason && len(reason) < 8 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required"})
		return
	}
	if !requireReason && reason == "" {
		reason = "approved by admin"
	}

	moderatorID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	err = h.repo.DecideDriverVerification(
		r.Context(),
		verificationID,
		status,
		reason,
		moderatorID,
		h.idGen.NewID(),
		h.clock.Now(),
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "verification not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"id":     verificationID,
		"status": status,
	})
}

func parseAdminLimit(r *http.Request, fallback int, max int) int {
	limit := fallback
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err == nil && parsed > 0 {
			limit = parsed
		}
	}
	if limit > max {
		return max
	}
	return limit
}

func sanitizeStringList(values []string, limit int) []string {
	if limit <= 0 {
		limit = 20
	}
	out := make([]string, 0, len(values))
	for _, value := range values {
		normalized := strings.TrimSpace(value)
		if normalized == "" {
			continue
		}
		if len(normalized) > 500 {
			normalized = normalized[:500]
		}
		out = append(out, normalized)
		if len(out) >= limit {
			break
		}
	}
	return out
}

func sanitizeObjectName(value string) string {
	value = strings.ReplaceAll(value, "\\", "/")
	parts := strings.Split(value, "/")
	value = parts[len(parts)-1]
	value = strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z':
			return r
		case r >= 'A' && r <= 'Z':
			return r
		case r >= '0' && r <= '9':
			return r
		case r == '.', r == '-', r == '_':
			return r
		default:
			return '-'
		}
	}, value)
	value = strings.Trim(value, ".-")
	if value == "" {
		return "document"
	}
	if len(value) > 120 {
		return value[:120]
	}
	return value
}
