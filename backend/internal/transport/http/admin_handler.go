package http

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	admindomain "evik/backend/internal/domain/admin"
	driverdomain "evik/backend/internal/domain/driver"
	"evik/backend/internal/infrastructure/storage"
	locationdomain "evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	"github.com/go-chi/chi/v5"
)

type AdminRepository interface {
	Overview(ctx context.Context) (admindomain.Overview, error)
	ListDriverVerifications(ctx context.Context, limit int) ([]admindomain.DriverVerification, error)
	UpsertDriverVerification(ctx context.Context, item admindomain.DriverVerification) error
	DecideDriverVerification(ctx context.Context, decision admindomain.DriverVerificationDecision) error
	ListUsers(ctx context.Context, limit int) ([]admindomain.User, error)
	ListReviews(ctx context.Context, limit int) ([]admindomain.Review, error)
	CreateReview(ctx context.Context, item admindomain.Review) error
	GetDriverReviews(ctx context.Context, driverID string, limit int) ([]admindomain.Review, DriverReviewsStats, error)
	GetOrderReview(ctx context.Context, orderID string) (*admindomain.Review, error)
	ListTaxProfiles(ctx context.Context, limit int) ([]AdminTaxProfile, error)
	UpdateTaxProfileStatus(ctx context.Context, driverID, status, adminComments string) error
}

type AdminTaxProfile struct {
	DriverID           string    `json:"driver_id"`
	INN                string    `json:"inn"`
	TaxpayerType       string    `json:"taxpayer_type"`
	VerificationStatus string    `json:"verification_status"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
	FullName           string    `json:"full_name,omitempty"`
}

type DriverReviewsStats struct {
	Total         int     `json:"total"`
	RatingAverage float64 `json:"rating_average"`
	RatingCount   int     `json:"rating_count"`
}

// AdminOrderRepository is the narrow contract the admin handler uses to
// power GET /admin/orders and GET /admin/orders/{id}. It is satisfied by
// the postgres OrderRepository.
type AdminOrderRepository interface {
	ListAdminOrders(ctx context.Context, filter orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error)
	GetAdminOrderDetails(ctx context.Context, orderID string) (*orderdomain.AdminOrderDetails, error)
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
	Endpoint      string
	Region        string
	Bucket        string
	AccessKey     string
	SecretKey     string
	PublicBaseURL string
}

type AdminHandler struct {
	repo         AdminRepository
	driverRepo   AdminDriverRepository
	locationRepo AdminLocationRepository
	orderRepo    AdminOrderRepository
	idGen        AdminIDGenerator
	clock        AdminClock
	storage      DocumentStorageConfig
	docStorage   *storage.DocumentStorage
}

func NewAdminHandler(
	repo AdminRepository,
	driverRepo AdminDriverRepository,
	locationRepo AdminLocationRepository,
	orderRepo AdminOrderRepository,
	idGen AdminIDGenerator,
	clock AdminClock,
	storageConfig DocumentStorageConfig,
) *AdminHandler {
	var docStorage *storage.DocumentStorage
	if storageConfig.Endpoint != "" && storageConfig.Bucket != "" && storageConfig.AccessKey != "" && storageConfig.SecretKey != "" {
		var err error
		docStorage, err = storage.NewDocumentStorage(
			storageConfig.Endpoint,
			storageConfig.AccessKey,
			storageConfig.SecretKey,
			storageConfig.Bucket,
			storageConfig.Region,
			storageConfig.PublicBaseURL,
		)
		if err != nil {
			log.Printf("Failed to initialize document storage: %v", err)
		}
	}

	return &AdminHandler{
		repo:         repo,
		driverRepo:   driverRepo,
		locationRepo: locationRepo,
		orderRepo:    orderRepo,
		idGen:        idGen,
		clock:        clock,
		storage:      storageConfig,
		docStorage:   docStorage,
	}
}

type adminDecisionRequest struct {
	Reason string `json:"reason"`
	// VehiclePlate / VehicleModel / VehicleType are required when the admin
	// is approving a driver verification — they're entered manually after
	// the admin reviews the uploaded photos / documents. Ignored for other
	// status transitions (rejected / changes_requested / blocked).
	VehiclePlate string `json:"vehicle_plate,omitempty"`
	VehicleModel string `json:"vehicle_model,omitempty"`
	VehicleType  string `json:"vehicle_type,omitempty"`
}

// allowedVehicleTypes mirrors the tow truck types known to the pricing
// domain. We validate here so the admin can't save garbage that would
// later break order pricing or matching.
var allowedVehicleTypes = map[string]struct{}{
	"winch":       {},
	"platform":    {},
	"manipulator": {},
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

	gmvByDay := make([]map[string]any, 0, len(overview.GMVByDay))
	for _, point := range overview.GMVByDay {
		gmvByDay = append(gmvByDay, map[string]any{"date": point.Date, "amount": point.Amount})
	}
	commissionByDay := make([]map[string]any, 0, len(overview.CommissionByDay))
	for _, point := range overview.CommissionByDay {
		commissionByDay = append(commissionByDay, map[string]any{"date": point.Date, "amount": point.Amount})
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

		// Phase 1 KPI. All amounts in kopecks (minor units).
		"gmv_today":                    overview.GMVToday,
		"gmv_month":                    overview.GMVMonth,
		"commission_today":             overview.CommissionToday,
		"commission_month":             overview.CommissionMonth,
		"payouts_today":                overview.PayoutsToday,
		"payouts_month":                overview.PayoutsMonth,
		"payouts_pending":              overview.PayoutsPending,
		"failed_payments":              overview.FailedPayments,
		"failed_payouts":               overview.FailedPayouts,
		"subscriptions_revenue_today":  overview.SubscriptionsRevenueToday,
		"subscriptions_revenue_month":  overview.SubscriptionsRevenueMonth,
		"cash_debt_total":              overview.CashDebtTotal,
		"active_drivers":               overview.ActiveDrivers,
		"pending_verifications":        overview.PendingVerifications,
		"gmv_by_day":                   gmvByDay,
		"commission_by_day":            commissionByDay,
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

	// Validate order exists and get its details
	orderDetails, err := h.orderRepo.GetAdminOrderDetails(r.Context(), orderID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "order not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to fetch order details"})
		return
	}

	// Validate order belongs to the authenticated client
	if orderDetails.Order.ClientID != clientID {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "you can only review your own orders"})
		return
	}

	// Validate order is completed
	if orderDetails.Order.Status != "completed" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "you can only review completed orders"})
		return
	}

	// Validate driver_id matches the order's driver
	if orderDetails.Order.DriverID != driverID {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "driver_id does not match the order driver"})
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
		// Check for duplicate review (unique constraint violation)
		if strings.Contains(err.Error(), "idx_driver_reviews_order_id") ||
		   strings.Contains(err.Error(), "duplicate key") ||
		   strings.Contains(err.Error(), "UNIQUE constraint") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "you have already reviewed this order"})
			return
		}
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

func (h *AdminHandler) GetDriverReviews(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	if driverID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "driver_id is required"})
		return
	}

	limit := parseAdminLimit(r, 50, 100)
	reviews, stats, err := h.repo.GetDriverReviews(r.Context(), driverID, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]map[string]any, 0, len(reviews))
	for _, review := range reviews {
		payload = append(payload, map[string]any{
			"id":          review.ID,
			"order_id":    review.OrderID,
			"stars":       review.Stars,
			"text":        review.Text,
			"client_id":   review.ClientID,
			"client_name": review.ClientName,
			"created_at":  review.CreatedAt.Format(time.RFC3339),
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"items":          payload,
		"total":          stats.Total,
		"rating_average": stats.RatingAverage,
		"rating_count":   stats.RatingCount,
	})
}

func (h *AdminHandler) GetOrderReview(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	if orderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "order_id is required"})
		return
	}

	review, err := h.repo.GetOrderReview(r.Context(), orderID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	if review == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "review not found"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"review": map[string]any{
			"id":          review.ID,
			"order_id":    review.OrderID,
			"driver_id":   review.DriverID,
			"client_id":   review.ClientID,
			"stars":       review.Stars,
			"text":        review.Text,
			"driver_name": review.DriverName,
			"client_name": review.ClientName,
			"created_at":  review.CreatedAt.Format(time.RFC3339),
		},
	})
}

func (h *AdminHandler) CreateDocumentUpload(w http.ResponseWriter, r *http.Request) {
	if h.docStorage == nil {
		writeJSON(w, http.StatusNotImplemented, map[string]string{"error": "document storage is not configured"})
		return
	}

	// Parse multipart form with 32MB max memory
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to parse multipart form"})
		return
	}

	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	// Extract document type
	documentType := strings.TrimSpace(r.FormValue("document_type"))
	if !storage.IsAllowedDocumentType(documentType) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid document_type. allowed: passport, license, vehicleDocs, vehiclePhoto, selfie",
		})
		return
	}

	// Get the uploaded file
	file, header, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing file in multipart form"})
		return
	}
	defer file.Close()

	// Validate content type
	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	if !storage.IsAllowedContentType(contentType) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid content type. allowed: image/jpeg, image/png, image/webp, application/pdf",
		})
		return
	}

	// Validate file size (10MB limit)
	const maxFileSize = 10 << 20
	if header.Size > maxFileSize {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("file too large. max size: %d bytes", maxFileSize),
		})
		return
	}

	// Ensure bucket exists
	if err := h.docStorage.EnsureBucket(r.Context()); err != nil {
		log.Printf("Failed to ensure bucket: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "storage setup failed"})
		return
	}

	// Upload the document
	uploadedDoc, err := h.docStorage.UploadDocument(
		r.Context(),
		userID,
		documentType,
		file,
		header.Size,
		contentType,
	)
	if err != nil {
		log.Printf("Failed to upload document: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "upload failed"})
		return
	}

	// Return successful response
	writeJSON(w, http.StatusCreated, map[string]any{
		"document": map[string]any{
			"key":         uploadedDoc.Key,
			"public_url":  uploadedDoc.PublicURL,
			"size":        uploadedDoc.Size,
			"content_type": contentType,
			"document_type": documentType,
		},
		"message": "document uploaded successfully",
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

	plate := strings.ToUpper(strings.TrimSpace(req.VehiclePlate))
	model := strings.TrimSpace(req.VehicleModel)
	vehicleType := strings.TrimSpace(req.VehicleType)

	if status == "approved" {
		// When approving, the admin must enter the vehicle data — we don't
		// trust whatever the driver originally submitted because the
		// approval is the moment the data becomes authoritative.
		if plate == "" || model == "" || vehicleType == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "vehicle_plate, vehicle_model and vehicle_type are required when approving",
			})
			return
		}
		if _, ok := allowedVehicleTypes[vehicleType]; !ok {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "vehicle_type must be one of winch, platform, manipulator",
			})
			return
		}
	}

	moderatorID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	err = h.repo.DecideDriverVerification(r.Context(), admindomain.DriverVerificationDecision{
		ID:           verificationID,
		Status:       status,
		Reason:       reason,
		ModeratorID:  moderatorID,
		AuditID:      h.idGen.NewID(),
		Now:          h.clock.Now(),
		VehiclePlate: plate,
		VehicleModel: model,
		VehicleType:  vehicleType,
	})
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "verification not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	// SMS notification stub. When a real SMS provider is wired in (Phase A
	// security MVP already issues OTPs via phone_otps but doesn't expose a
	// generic sender), this is the single point that needs to be replaced.
	if status == "approved" {
		log.Printf("[sms-stub] driver verification %s approved — would notify driver via SMS", verificationID)
	} else if status == "rejected" || status == "changes_requested" {
		log.Printf("[sms-stub] driver verification %s %s — would notify driver via SMS with reason", verificationID, status)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"id":     verificationID,
		"status": status,
	})
}

// ListAdminOrders serves GET /admin/orders with filters. All money values
// in the response are in kopecks (minor units). The response shape is:
//
//	{ "items": [...], "total": N, "limit": L, "offset": O }
func (h *AdminHandler) ListAdminOrders(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	filter := orderdomain.AdminOrderFilter{
		Status:          strings.TrimSpace(q.Get("status")),
		PaymentMethod:   strings.TrimSpace(q.Get("payment_method")),
		FinancialStatus: strings.TrimSpace(q.Get("financial_status")),
		DriverID:        strings.TrimSpace(q.Get("driver_id")),
		ClientID:        strings.TrimSpace(q.Get("client_id")),
		Limit:           parseAdminLimit(r, 50, 200),
		Offset:          parseAdminOffset(r),
	}
	if from, ok := parseAdminTime(q.Get("from")); ok {
		filter.From = &from
	}
	if to, ok := parseAdminTime(q.Get("to")); ok {
		filter.To = &to
	}

	items, total, err := h.orderRepo.ListAdminOrders(r.Context(), filter)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]map[string]any, 0, len(items))
	for _, item := range items {
		payload = append(payload, adminOrderItemJSON(item))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  payload,
		"total":  total,
		"limit":  filter.Limit,
		"offset": filter.Offset,
	})
}

// GetAdminOrderDetails serves GET /admin/orders/{orderID}.
func (h *AdminHandler) GetAdminOrderDetails(w http.ResponseWriter, r *http.Request) {
	orderID := strings.TrimSpace(chi.URLParam(r, "orderID"))
	if orderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "order id is required"})
		return
	}
	details, err := h.orderRepo.GetAdminOrderDetails(r.Context(), orderID)
	if err != nil {
		if errors.Is(err, orderdomain.ErrOrderNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "order not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	timeline := make([]map[string]any, 0, len(details.Timeline))
	for _, event := range details.Timeline {
		timeline = append(timeline, map[string]any{
			"at":     event.At.Format(time.RFC3339),
			"status": event.Status,
		})
	}

	walletTxs := make([]map[string]any, 0, len(details.WalletTransactions))
	for _, tx := range details.WalletTransactions {
		walletTxs = append(walletTxs, map[string]any{
			"id":          tx.ID,
			"driver_id":   tx.DriverID,
			"type":        tx.Type,
			"direction":   tx.Direction,
			"amount":      tx.Amount,
			"status":      tx.Status,
			"description": tx.Description,
			"created_at":  tx.CreatedAt.Format(time.RFC3339),
		})
	}

	payouts := make([]map[string]any, 0, len(details.Payouts))
	for _, p := range details.Payouts {
		payouts = append(payouts, map[string]any{
			"id":         p.ID,
			"driver_id":  p.DriverID,
			"amount":     p.Amount,
			"status":     p.Status,
			"created_at": p.CreatedAt.Format(time.RFC3339),
		})
	}

	refunds := make([]map[string]any, 0, len(details.Refunds))
	for _, ref := range details.Refunds {
		refunds = append(refunds, map[string]any{
			"id":         ref.ID,
			"payment_id": ref.PaymentID,
			"amount":     ref.Amount,
			"status":     ref.Status,
			"reason":     ref.Reason,
			"created_at": ref.CreatedAt.Format(time.RFC3339),
		})
	}

	var payment map[string]any
	if details.Payment != nil {
		payment = map[string]any{
			"id":                  details.Payment.ID,
			"provider":            details.Payment.Provider,
			"provider_payment_id": details.Payment.ProviderPaymentID,
			"payment_method":      details.Payment.PaymentMethod,
			"amount":              details.Payment.Amount,
			"status":              details.Payment.Status,
			"paid_at":             formatNullableTime(details.Payment.PaidAt),
			"created_at":          details.Payment.CreatedAt.Format(time.RFC3339),
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"order":          adminOrderItemJSON(details.Order),
		"pickup":         map[string]any{"lat": details.Pickup.Lat, "lng": details.Pickup.Lng},
		"dropoff":        map[string]any{"lat": details.Dropoff.Lat, "lng": details.Dropoff.Lng},
		"tow_truck_type": details.TowTruckType,
		"timeline":       timeline,
		"payment":        payment,
		"wallet_transactions": walletTxs,
		"payouts":             payouts,
		"refunds":             refunds,
		"financial_breakdown": map[string]any{
			"total_amount":         details.FinancialBreakdown.TotalAmount,
			"commission_amount":    details.FinancialBreakdown.CommissionAmount,
			"driver_amount":        details.FinancialBreakdown.DriverAmount,
			"cash_commission_hold": details.FinancialBreakdown.CashCommissionHold,
			"platform_net_amount":  details.FinancialBreakdown.PlatformNetAmount,
		},
	})
}

// ListTaxProfiles serves GET /admin/tax-profiles.
// Returns all driver tax profiles for admin review and verification.
func (h *AdminHandler) ListTaxProfiles(w http.ResponseWriter, r *http.Request) {
	profiles, err := h.repo.ListTaxProfiles(r.Context(), parseAdminLimit(r, 50, 100))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	payload := make([]map[string]any, 0, len(profiles))
	for _, profile := range profiles {
		payload = append(payload, map[string]any{
			"driver_id":             profile.DriverID,
			"inn":                   profile.INN,
			"taxpayer_type":         profile.TaxpayerType,
			"verification_status":   profile.VerificationStatus,
			"full_name":             profile.FullName,
			"created_at":            profile.CreatedAt.Format(time.RFC3339),
			"updated_at":            profile.UpdatedAt.Format(time.RFC3339),
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{"items": payload})
}

// VerifyTaxProfile serves POST /admin/tax-profiles/{driverID}/verify.
// Marks a driver's tax profile as verified by admin.
func (h *AdminHandler) VerifyTaxProfile(w http.ResponseWriter, r *http.Request) {
	h.updateTaxProfileStatus(w, r, "verified", false)
}

// RejectTaxProfile serves POST /admin/tax-profiles/{driverID}/reject.
// Marks a driver's tax profile as rejected by admin with optional reason.
func (h *AdminHandler) RejectTaxProfile(w http.ResponseWriter, r *http.Request) {
	h.updateTaxProfileStatus(w, r, "rejected", true)
}

// RequestTaxProfileChanges serves POST /admin/tax-profiles/{driverID}/request-changes.
// Requests changes to a driver's tax profile with admin comments.
func (h *AdminHandler) RequestTaxProfileChanges(w http.ResponseWriter, r *http.Request) {
	h.updateTaxProfileStatus(w, r, "changes_requested", true)
}

func (h *AdminHandler) updateTaxProfileStatus(w http.ResponseWriter, r *http.Request, status string, requireComments bool) {
	driverID := strings.TrimSpace(chi.URLParam(r, "driverID"))
	if driverID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "driver ID is required"})
		return
	}

	var req struct {
		Comments string `json:"comments"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	comments := strings.TrimSpace(req.Comments)
	if requireComments && comments == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "comments are required for this action"})
		return
	}

	if err := h.repo.UpdateTaxProfileStatus(r.Context(), driverID, status, comments); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"driver_id": driverID,
		"status":    status,
		"message":   fmt.Sprintf("Tax profile %s successfully", status),
	})
}

func adminOrderItemJSON(item orderdomain.AdminOrderListItem) map[string]any {
	return map[string]any{
		"order_id":          item.OrderID,
		"client_id":         item.ClientID,
		"client_name":       item.ClientName,
		"client_phone":      item.ClientPhone,
		"driver_id":         item.DriverID,
		"driver_name":       item.DriverName,
		"driver_phone":      item.DriverPhone,
		"status":            item.Status,
		"payment_method":    item.PaymentMethod,
		"payment_status":    item.PaymentStatus,
		"financial_status":  item.FinancialStatus,
		"price_total":       item.PriceTotal,
		"commission_amount": item.CommissionAmount,
		"driver_amount":     item.DriverAmount,
		"created_at":        item.CreatedAt.Format(time.RFC3339),
		"completed_at":      formatNullableTime(item.CompletedAt),
		"cancelled_at":      formatNullableTime(item.CancelledAt),
	}
}

func formatNullableTime(t *time.Time) any {
	if t == nil {
		return nil
	}
	return t.Format(time.RFC3339)
}

// parseAdminOffset parses ?offset=N from the request URL, clamped to >= 0.
func parseAdminOffset(r *http.Request) int {
	raw := strings.TrimSpace(r.URL.Query().Get("offset"))
	if raw == "" {
		return 0
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < 0 {
		return 0
	}
	return value
}

// parseAdminTime accepts ISO-8601 (RFC3339) or YYYY-MM-DD values.
func parseAdminTime(raw string) (time.Time, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, false
	}
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		return t, true
	}
	if t, err := time.Parse("2006-01-02", raw); err == nil {
		return t, true
	}
	return time.Time{}, false
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
