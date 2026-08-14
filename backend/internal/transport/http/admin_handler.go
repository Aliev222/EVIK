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

	"evik/backend/internal/auth"
	admindomain "evik/backend/internal/domain/admin"
	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/storage"
	"github.com/go-chi/chi/v5"
)

type AdminListPayment struct {
	ID              string `json:"id"`
	OrderID         string `json:"order_id"`
	UserID          string `json:"user_id"`
	Provider        string `json:"provider"`
	ProviderPayment string `json:"provider_payment_id"`
	PaymentMethod   string `json:"payment_method"`
	Amount          int64  `json:"amount"`
	Currency        string `json:"currency"`
	Status          string `json:"status"`
	CreatedAt       string `json:"created_at"`
}

type AdminListWallet struct {
	ID              string `json:"id"`
	DriverID        string `json:"driver_id"`
	Available       int64  `json:"available_balance"`
	Pending         int64  `json:"pending_balance"`
	Debt            int64  `json:"debt_balance"`
	Currency        string `json:"currency"`
	UpdatedAt       string `json:"updated_at"`
}

type AdminListTransaction struct {
	ID          string `json:"id"`
	WalletID    string `json:"wallet_id"`
	DriverID    string `json:"driver_id"`
	OrderID     string `json:"order_id"`
	PaymentID   string `json:"payment_id"`
	PayoutID    string `json:"payout_id"`
	Type        string `json:"type"`
	Direction   string `json:"direction"`
	Amount      int64  `json:"amount"`
	Currency    string `json:"currency"`
	Status      string `json:"status"`
	Description string `json:"description"`
	CreatedAt   string `json:"created_at"`
}

type AdminListSubscription struct {
	ID        string `json:"id"`
	DriverID  string `json:"driver_id"`
	PlanID    string `json:"plan_id"`
	PaymentID string `json:"payment_id"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
}

type AdminAuditLogEntry struct {
	ID           string `json:"id"`
	EntityType   string `json:"entity_type"`
	EntityID     string `json:"entity_id"`
	Action       string `json:"action"`
	Reason       string `json:"reason"`
	ModeratorID  string `json:"moderator_id"`
	CreatedAt    string `json:"created_at"`
}

type AdminRepository interface {
	Overview(ctx context.Context) (admindomain.Overview, error)
	ListDriverVerifications(ctx context.Context, limit int) ([]admindomain.DriverVerification, error)
	UpsertDriverVerification(ctx context.Context, item admindomain.DriverVerification) error
	DecideDriverVerification(ctx context.Context, decision admindomain.DriverVerificationDecision) error
	ListUsers(ctx context.Context, limit int) ([]admindomain.User, error)
	ListReviews(ctx context.Context, limit int, offset int, stars int, driverQuery string) ([]admindomain.Review, int64, error)
	CreateReview(ctx context.Context, item admindomain.Review) error
	GetDriverReviews(ctx context.Context, driverID string, limit int) ([]admindomain.Review, DriverReviewsStats, error)
	GetDriverRating(ctx context.Context, driverID string) (DriverReviewsStats, error)
	GetOrderReview(ctx context.Context, orderID string) (*admindomain.Review, error)
	HideReview(ctx context.Context, id string) error
	ShowReview(ctx context.Context, id string) error
	DeleteReview(ctx context.Context, id string) error
	ListTaxProfiles(ctx context.Context, limit int) ([]AdminTaxProfile, error)
	UpdateTaxProfileStatus(ctx context.Context, driverID, status, adminComments string) error
	GetDriverDetail(ctx context.Context, driverID string) (*AdminDriverDetail, error)
	ListDriverOrders(ctx context.Context, driverID string, limit int, offset int) ([]orderdomain.AdminOrderListItem, int64, error)
	ListAdminPayments(ctx context.Context, limit, offset int) ([]AdminListPayment, int64, error)
	ListAdminWallets(ctx context.Context, limit, offset int, search string) ([]AdminListWallet, int64, error)
	ListAdminTransactions(ctx context.Context, limit, offset int, txType, driverID string) ([]AdminListTransaction, int64, error)
	ListAdminSubscriptions(ctx context.Context, limit, offset int, status string) ([]AdminListSubscription, int64, error)
	ListAuditLog(ctx context.Context, limit, offset int, entityType, action string) ([]AdminAuditLogEntry, int64, error)
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

type AdminDriverDetail struct {
	DriverID     string               `json:"driver_id"`
	UserID       string               `json:"user_id"`
	FullName     string               `json:"full_name"`
	Phone        string               `json:"phone"`
	Status       string               `json:"status"`
	OrdersCount  int64                `json:"orders_count"`
	Verification *AdminVerificationInfo `json:"verification,omitempty"`
	TaxProfile   *AdminTaxProfileInfo   `json:"tax_profile,omitempty"`
	Wallet       *AdminWalletInfo       `json:"wallet,omitempty"`
	Reviews      *AdminReviewsSummary   `json:"reviews,omitempty"`
}

type AdminVerificationInfo struct {
	ID             string   `json:"id"`
	Vehicle        string   `json:"vehicle"`
	Plate          string   `json:"plate"`
	VehicleType    string   `json:"vehicle_type"`
	Status         string   `json:"status"`
	Risk           string   `json:"risk"`
	SubmittedAt    string   `json:"submitted_at"`
	Documents      []string `json:"documents"`
	DecisionReason *string  `json:"decision_reason"`
}

type AdminTaxProfileInfo struct {
	INN                string `json:"inn"`
	TaxpayerType       string `json:"taxpayer_type"`
	VerificationStatus string `json:"verification_status"`
	CreatedAt          string `json:"created_at"`
}

type AdminWalletInfo struct {
	Available int64  `json:"available"`
	Pending   int64  `json:"pending"`
	Debt      int64  `json:"debt"`
	Currency  string `json:"currency"`
	UpdatedAt string `json:"updated_at"`
}

type AdminReviewsSummary struct {
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
	GetLocations(ctx context.Context, driverIDs []string) (map[string]*locationdomain.Location, error)
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

// @Summary      Admin overview
// @Description  Returns admin dashboard overview with KPIs, recent stats, and GMV data.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "overview with KPIs and charts"
// @Router       /admin/overview [get]
func (h *AdminHandler) Overview(w http.ResponseWriter, r *http.Request) {
	overview, err := h.repo.Overview(r.Context())
	if err != nil {
		writeInternalError(w, err)
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

// @Summary      List driver verifications (admin)
// @Description  Returns all driver verification requests for admin review.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of driver verifications"
// @Router       /admin/driver-verifications [get]
func (h *AdminHandler) ListDriverVerifications(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.ListDriverVerifications(r.Context(), parseAdminLimit(r, 50, 100))
	if err != nil {
		writeInternalError(w, err)
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

// @Summary      List users (admin)
// @Description  Returns a list of all platform users for admin management.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of users"
// @Router       /admin/users [get]
func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.ListUsers(r.Context(), parseAdminLimit(r, 100, 200))
	if err != nil {
		writeInternalError(w, err)
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

// @Summary      List reviews (admin)
// @Description  Returns all driver reviews across the platform.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        limit        query  int     false  "Max items (default 50, max 200)"
// @Param        offset       query  int     false  "Pagination offset"
// @Param        stars        query  int     false  "Filter by star rating (1-5)"
// @Param        driver_query query  string  false  "Search by driver ID or name"
// @Success      200  {object}  map[string]any  "list of reviews"
// @Router       /admin/reviews [get]
func (h *AdminHandler) ListReviews(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	stars := 0
	if s := strings.TrimSpace(q.Get("stars")); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v >= 1 && v <= 5 {
			stars = v
		}
	}
	driverQuery := strings.TrimSpace(q.Get("driver_query"))

	items, total, err := h.repo.ListReviews(r.Context(), parseAdminLimit(r, 50, 200), parseAdminOffset(r), stars, driverQuery)
	if err != nil {
		writeInternalError(w, err)
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
			"is_hidden":   item.IsHidden,
			"created_at":  item.CreatedAt.Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  payload,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

// @Summary      Hide review (admin)
// @Description  Hides a driver review from public view.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        reviewID  path  string  true  "Review ID"
// @Success      200  {object}  map[string]any  "hidden status"
// @Router       /admin/reviews/{reviewID}/hide [post]
func (h *AdminHandler) HideReview(w http.ResponseWriter, r *http.Request) {
	reviewID := strings.TrimSpace(chi.URLParam(r, "reviewID"))
	if reviewID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "review id is required"})
		return
	}
	if err := h.repo.HideReview(r.Context(), reviewID); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "hidden"})
}

// @Summary      Show review (admin)
// @Description  Unhides a previously hidden driver review.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        reviewID  path  string  true  "Review ID"
// @Success      200  {object}  map[string]any  "shown status"
// @Router       /admin/reviews/{reviewID}/show [post]
func (h *AdminHandler) ShowReview(w http.ResponseWriter, r *http.Request) {
	reviewID := strings.TrimSpace(chi.URLParam(r, "reviewID"))
	if reviewID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "review id is required"})
		return
	}
	if err := h.repo.ShowReview(r.Context(), reviewID); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "shown"})
}

// @Summary      Delete review (admin)
// @Description  Permanently deletes a driver review.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        reviewID  path  string  true  "Review ID"
// @Success      200  {object}  map[string]any  "deleted status"
// @Router       /admin/reviews/{reviewID} [delete]
func (h *AdminHandler) DeleteReview(w http.ResponseWriter, r *http.Request) {
	reviewID := strings.TrimSpace(chi.URLParam(r, "reviewID"))
	if reviewID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "review id is required"})
		return
	}
	if err := h.repo.DeleteReview(r.Context(), reviewID); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "deleted"})
}

// @Summary      Submit driver verification
// @Description  Submits driver documents and personal info for verification. Drivers submit their own; admins can submit on behalf.
// @Tags         drivers
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      SubmitDriverVerificationRequest  true  "Verification payload"
// @Success      201   {object}  map[string]any  "created verification"
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Failure      401   {object}  ErrorResponse  "unauthorized"
// @Router       /driver-verifications [post]
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
		if errors.Is(err, admindomain.ErrDriverVerificationBlocked) {
			// A blocked verification cannot be overwritten by a driver (or an
			// admin submitting on their behalf) — the block is sticky and only
			// an explicit admin decision can lift it.
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "аккаунт заблокирован, обратитесь в поддержку",
			})
			return
		}
		writeInternalError(w, err)
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

// @Summary      Create review
// @Description  Creates a review (rating with optional text) for a completed order and driver.
// @Tags         reviews
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateReviewRequest  true  "Review payload"
// @Success      201   {object}  map[string]any  "created review"
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Failure      401   {object}  ErrorResponse  "unauthorized"
// @Router       /reviews [post]
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
		writeInternalError(w, err)
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

// @Summary      Get driver reviews
// @Description  Returns reviews and rating stats for a specific driver.
// @Tags         reviews
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "reviews with rating stats"
// @Failure      400  {object}  ErrorResponse  "driver_id is required"
// @Router       /drivers/{driverID}/reviews [get]
func (h *AdminHandler) GetDriverReviews(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "driverID")
	if driverID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "driver_id is required"})
		return
	}

	// Review texts are private. Only admins may read them. Everyone else gets
	// the aggregated rating computed over non-hidden reviews — no texts, no
	// moderated-away (hidden) entries.
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if role != auth.RoleAdmin {
		stats, err := h.repo.GetDriverRating(r.Context(), driverID)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"items":          []any{},
			"total":          0,
			"rating_average": stats.RatingAverage,
			"rating_count":   stats.RatingCount,
		})
		return
	}

	limit := parseAdminLimit(r, 50, 100)
	reviews, stats, err := h.repo.GetDriverReviews(r.Context(), driverID, limit)
	if err != nil {
		writeInternalError(w, err)
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

// @Summary      Get order review
// @Description  Returns the review for a specific order.
// @Tags         reviews
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string  true  "Order ID"
// @Success      200  {object}  map[string]any  "review details"
// @Failure      400  {object}  ErrorResponse  "order_id is required"
// @Failure      404  {object}  ErrorResponse  "review not found"
// @Router       /orders/{orderID}/review [get]
func (h *AdminHandler) GetOrderReview(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	if orderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "order_id is required"})
		return
	}

	review, err := h.repo.GetOrderReview(r.Context(), orderID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if review == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "review not found"})
		return
	}

	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	// The written review text is private: it is visible to admins and to the
	// participants of the order it belongs to (the authoring client and the
	// order's driver). Any other authenticated user gets 403 Forbidden; a
	// genuinely missing review keeps returning 404.
	if role != auth.RoleAdmin && review.ClientID != userID && review.DriverID != userID {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
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

// @Summary      Upload document
// @Description  Uploads a driver document (passport, license, vehicle photo, selfie) to S3-compatible storage. Multipart form.
// @Tags         drivers
// @Accept       mpfd
// @Produce      json
// @Security     BearerAuth
// @Param        document_type  formData  string  true  "Document type"  Enums(passport,license,vehicleDocs,vehiclePhoto,selfie)
// @Param        file            formData  file    true  "Document file"
// @Success      200  {object}  map[string]any  "uploaded document info"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      501  {object}  ErrorResponse  "storage not configured"
// @Router       /driver-documents/uploads [post]
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

// @Summary      List online drivers (admin)
// @Description  Returns currently online drivers with their last known locations for the live map.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "online drivers with locations"
// @Router       /admin/drivers-online [get]
func (h *AdminHandler) ListOnlineDrivers(w http.ResponseWriter, r *http.Request) {
	drivers, err := h.driverRepo.ListActive(r.Context(), parseAdminLimit(r, 100, 200))
	if err != nil {
		writeInternalError(w, err)
		return
	}

	driverIDs := make([]string, len(drivers))
	for i, d := range drivers {
		driverIDs[i] = d.ID
	}
	locations, err := h.locationRepo.GetLocations(r.Context(), driverIDs)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	payload := make([]adminDriverLocationResponse, 0, len(drivers))
	for _, driver := range drivers {
		loc, ok := locations[driver.ID]
		if !ok {
			continue
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

// @Summary      Get driver detail (admin)
// @Description  Returns full driver profile with verification, tax, wallet, orders, and reviews.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  AdminDriverDetail  "driver detail"
// @Router       /admin/drivers/{driverID} [get]
func (h *AdminHandler) GetDriverDetail(w http.ResponseWriter, r *http.Request) {
	driverID := strings.TrimSpace(chi.URLParam(r, "driverID"))
	if driverID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "driver id is required"})
		return
	}

	detail, err := h.repo.GetDriverDetail(r.Context(), driverID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if detail == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "driver not found"})
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

// @Summary      List driver orders (admin)
// @Description  Returns paginated orders for a specific driver.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Param        limit     query  int     false  "Max items (default 50, max 200)"
// @Param        offset    query  int     false  "Pagination offset"
// @Success      200  {object}  map[string]any  "driver orders"
// @Router       /admin/drivers/{driverID}/orders [get]
func (h *AdminHandler) ListDriverOrders(w http.ResponseWriter, r *http.Request) {
	driverID := strings.TrimSpace(chi.URLParam(r, "driverID"))
	if driverID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "driver id is required"})
		return
	}

	items, total, err := h.repo.ListDriverOrders(r.Context(), driverID, parseAdminLimit(r, 50, 200), parseAdminOffset(r))
	if err != nil {
		writeInternalError(w, err)
		return
	}

	payload := make([]map[string]any, 0, len(items))
	for _, item := range items {
		payload = append(payload, adminOrderItemJSON(item))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  payload,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

// @Summary      List payments (admin)
// @Description  Returns paginated list of payments with filters.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        limit   query  int     false  "Max items (default 50, max 200)"
// @Param        offset  query  int     false  "Pagination offset"
// @Success      200  {object}  map[string]any  "payments list"
// @Router       /admin/finance-v2/payments [get]
func (h *AdminHandler) ListAdminPayments(w http.ResponseWriter, r *http.Request) {
	items, total, err := h.repo.ListAdminPayments(r.Context(), parseAdminLimit(r, 50, 200), parseAdminOffset(r))
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  items,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

// @Summary      List wallets (admin)
// @Description  Returns paginated list of driver wallets with filters.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        limit   query  int     false  "Max items (default 50, max 200)"
// @Param        offset  query  int     false  "Pagination offset"
// @Param        search  query  string  false  "Search by driver ID"
// @Success      200  {object}  map[string]any  "wallets list"
// @Router       /admin/finance-v2/wallets [get]
func (h *AdminHandler) ListAdminWallets(w http.ResponseWriter, r *http.Request) {
	search := strings.TrimSpace(r.URL.Query().Get("search"))
	items, total, err := h.repo.ListAdminWallets(r.Context(), parseAdminLimit(r, 50, 200), parseAdminOffset(r), search)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  items,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

// @Summary      List transactions (admin)
// @Description  Returns paginated list of wallet transactions with filters.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        limit     query  int     false  "Max items (default 50, max 200)"
// @Param        offset    query  int     false  "Pagination offset"
// @Param        type      query  string  false  "Filter by transaction type"
// @Param        driver_id query  string  false  "Filter by driver ID"
// @Success      200  {object}  map[string]any  "transactions list"
// @Router       /admin/finance-v2/transactions [get]
func (h *AdminHandler) ListAdminTransactions(w http.ResponseWriter, r *http.Request) {
	txType := strings.TrimSpace(r.URL.Query().Get("type"))
	driverID := strings.TrimSpace(r.URL.Query().Get("driver_id"))
	items, total, err := h.repo.ListAdminTransactions(r.Context(), parseAdminLimit(r, 50, 200), parseAdminOffset(r), txType, driverID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  items,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

// @Summary      List subscriptions (admin)
// @Description  Returns paginated list of driver subscriptions with filters.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        limit   query  int     false  "Max items (default 50, max 200)"
// @Param        offset  query  int     false  "Pagination offset"
// @Param        status  query  string  false  "Filter by status"
// @Success      200  {object}  map[string]any  "subscriptions list"
// @Router       /admin/finance-v2/subscriptions [get]
func (h *AdminHandler) ListAdminSubscriptions(w http.ResponseWriter, r *http.Request) {
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	items, total, err := h.repo.ListAdminSubscriptions(r.Context(), parseAdminLimit(r, 50, 200), parseAdminOffset(r), status)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  items,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

// @Summary      List audit log (admin)
// @Description  Returns moderation audit log entries.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        limit       query  int     false  "Max items (default 50, max 200)"
// @Param        offset      query  int     false  "Pagination offset"
// @Param        entity_type query  string  false  "Filter by entity type"
// @Param        action      query  string  false  "Filter by action"
// @Success      200  {object}  map[string]any  "audit log entries"
// @Router       /admin/audit-log [get]
func (h *AdminHandler) ListAuditLog(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	entityType := strings.TrimSpace(q.Get("entity_type"))
	action := strings.TrimSpace(q.Get("action"))
	items, total, err := h.repo.ListAuditLog(r.Context(), parseAdminLimit(r, 50, 200), parseAdminOffset(r), entityType, action)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  items,
		"total":  total,
		"limit":  parseAdminLimit(r, 50, 200),
		"offset": parseAdminOffset(r),
	})
}

type batchModerationRequest struct {
	IDs          []string `json:"ids"`
	Reason       string   `json:"reason"`
	VehiclePlate string   `json:"vehicle_plate,omitempty"`
	VehicleModel string   `json:"vehicle_model,omitempty"`
	VehicleType  string   `json:"vehicle_type,omitempty"`
}

// @Summary      Batch approve verifications (admin)
// @Description  Approves multiple driver verifications at once.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body  batchModerationRequest  true  "IDs and vehicle details"
// @Success      200  {object}  map[string]any  "batch results"
// @Router       /admin/moderation/batch/approve [post]
func (h *AdminHandler) BatchApproveVerifications(w http.ResponseWriter, r *http.Request) {
	var req batchModerationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if len(req.IDs) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ids are required"})
		return
	}
	moderatorID, _ := userIDFromContext(r.Context())
	now := h.clock.Now()
	results := make([]map[string]any, 0, len(req.IDs))
	for _, id := range req.IDs {
		err := h.repo.DecideDriverVerification(r.Context(), admindomain.DriverVerificationDecision{
			ID:           id,
			Status:       "approved",
			Reason:       req.Reason,
			ModeratorID:  moderatorID,
			AuditID:      h.idGen.NewID(),
			Now:          now,
			VehiclePlate: req.VehiclePlate,
			VehicleModel: req.VehicleModel,
			VehicleType:  req.VehicleType,
		})
		if err != nil {
			log.Printf("ERROR: batch moderation %s %s: %v", "approved", id, err)
			results = append(results, map[string]any{"id": id, "status": "error", "error": "approval failed"})
		} else {
			results = append(results, map[string]any{"id": id, "status": "approved"})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": results})
}

// @Summary      Batch reject verifications (admin)
// @Description  Rejects multiple driver verifications at once.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body  batchModerationRequest  true  "IDs and reason"
// @Success      200  {object}  map[string]any  "batch results"
// @Router       /admin/moderation/batch/reject [post]
func (h *AdminHandler) BatchRejectVerifications(w http.ResponseWriter, r *http.Request) {
	var req batchModerationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if len(req.IDs) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ids are required"})
		return
	}
	if len(req.Reason) < 8 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required (min 8 chars)"})
		return
	}
	moderatorID, _ := userIDFromContext(r.Context())
	now := h.clock.Now()
	results := make([]map[string]any, 0, len(req.IDs))
	for _, id := range req.IDs {
		err := h.repo.DecideDriverVerification(r.Context(), admindomain.DriverVerificationDecision{
			ID:          id,
			Status:      "rejected",
			Reason:      req.Reason,
			ModeratorID: moderatorID,
			AuditID:     h.idGen.NewID(),
			Now:         now,
		})
		if err != nil {
			log.Printf("ERROR: batch moderation %s %s: %v", "rejected", id, err)
			results = append(results, map[string]any{"id": id, "status": "error", "error": "rejection failed"})
		} else {
			results = append(results, map[string]any{"id": id, "status": "rejected"})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": results})
}

// @Summary      Approve verification (admin)
// @Description  Approves a driver's document verification with optional vehicle details.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        verificationID  path  string                true  "Verification ID"
// @Param        body            body  AdminDecisionRequest  true  "Decision with vehicle details"
// @Success      200  {object}  map[string]any  "approval status"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Router       /admin/moderation/driver-verifications/{verificationID}/approve [post]
func (h *AdminHandler) ApproveDriverVerification(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "approved", false)
}

// @Summary      Reject verification (admin)
// @Description  Rejects a driver's document verification with a reason.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        verificationID  path  string                true  "Verification ID"
// @Param        body            body  AdminDecisionRequest  true  "Decision with reason"
// @Success      200  {object}  map[string]any  "rejection status"
// @Failure      400  {object}  ErrorResponse  "reason required"
// @Router       /admin/moderation/driver-verifications/{verificationID}/reject [post]
func (h *AdminHandler) RejectDriverVerification(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "rejected", true)
}

// @Summary      Request verification changes (admin)
// @Description  Requests changes to a driver's verification submission with admin feedback.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        verificationID  path  string                true  "Verification ID"
// @Param        body            body  AdminDecisionRequest  true  "Decision with reason"
// @Success      200  {object}  map[string]any  "update status"
// @Failure      400  {object}  ErrorResponse  "reason required"
// @Router       /admin/moderation/driver-verifications/{verificationID}/request-changes [post]
func (h *AdminHandler) RequestDriverVerificationChanges(w http.ResponseWriter, r *http.Request) {
	h.decideDriverVerification(w, r, "changes_requested", true)
}

// @Summary      Block verification (admin)
// @Description  Blocks a driver's verification. Admin-only endpoint.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        verificationID  path  string                true  "Verification ID"
// @Param        body            body  AdminDecisionRequest  true  "Decision with reason"
// @Success      200  {object}  map[string]any  "block status"
// @Failure      400  {object}  ErrorResponse  "reason required"
// @Router       /admin/moderation/driver-verifications/{verificationID}/block [post]
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
		if errors.Is(err, admindomain.ErrVehicleDataRequired) ||
			errors.Is(err, admindomain.ErrVehicleTypeNotAllowed) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		if errors.Is(err, admindomain.ErrInvalidDecisionStatus) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeInternalError(w, err)
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

// @Summary      List orders (admin)
// @Description  Returns paginated orders with filters. All money values in kopecks.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        status           query  string  false  "Filter by status"  Enums(searching,accepted,arrived,in_progress,completed,cancelled)
// @Param        payment_method   query  string  false  "Filter by payment method"  Enums(cash,card)
// @Param        financial_status query  string  false  "Filter by financial status"
// @Param        driver_id        query  string  false  "Filter by driver ID"
// @Param        client_id        query  string  false  "Filter by client ID"
// @Param        from             query  string  false  "Start date (RFC3339)"
// @Param        to               query  string  false  "End date (RFC3339)"
// @Param        limit            query  int     false  "Max items (default 50, max 200)"
// @Param        offset           query  int     false  "Pagination offset"
// @Success      200  {object}  map[string]any  "paginated orders"
// @Router       /admin/orders [get]
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
		writeInternalError(w, err)
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

// @Summary      Get order details (admin)
// @Description  Returns full order details with financial breakdown, payment info, driver profile, and wallet transactions.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string  true  "Order ID"
// @Success      200  {object}  map[string]any  "full order details"
// @Failure      400  {object}  ErrorResponse  "order_id is required"
// @Failure      404  {object}  ErrorResponse  "order not found"
// @Router       /admin/orders/{orderID} [get]
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
		writeInternalError(w, err)
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

// @Summary      List tax profiles (admin)
// @Description  Returns all driver tax profiles for admin review and verification.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of tax profiles"
// @Router       /admin/tax-profiles [get]
func (h *AdminHandler) ListTaxProfiles(w http.ResponseWriter, r *http.Request) {
	profiles, err := h.repo.ListTaxProfiles(r.Context(), parseAdminLimit(r, 50, 100))
	if err != nil {
		writeInternalError(w, err)
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

// @Summary      Verify tax profile (admin)
// @Description  Marks a driver's tax profile as verified.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "updated status"
// @Failure      400  {object}  ErrorResponse  "driver ID required"
// @Router       /admin/tax-profiles/{driverID}/verify [post]
func (h *AdminHandler) VerifyTaxProfile(w http.ResponseWriter, r *http.Request) {
	h.updateTaxProfileStatus(w, r, "verified", false)
}

// @Summary      Reject tax profile (admin)
// @Description  Rejects a driver's tax profile with admin comments.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "updated status"
// @Failure      400  {object}  ErrorResponse  "comments required or driver ID required"
// @Router       /admin/tax-profiles/{driverID}/reject [post]
func (h *AdminHandler) RejectTaxProfile(w http.ResponseWriter, r *http.Request) {
	h.updateTaxProfileStatus(w, r, "rejected", true)
}

// @Summary      Request tax profile changes (admin)
// @Description  Requests changes to a driver's tax profile with admin comments.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        driverID  path  string  true  "Driver ID"
// @Success      200  {object}  map[string]any  "updated status"
// @Failure      400  {object}  ErrorResponse  "comments required or driver ID required"
// @Router       /admin/tax-profiles/{driverID}/request-changes [post]
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
		writeInternalError(w, err)
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
