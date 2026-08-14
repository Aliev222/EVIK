package http

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"strconv"
	"time"

	"evik/backend/internal/auth"
	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	servicearea "evik/backend/internal/domain/servicearea"
	driveruc "evik/backend/internal/usecase/driver"
	orderuc "evik/backend/internal/usecase/order"
	"github.com/go-chi/chi/v5"
)

// DriverCityCache reads the city cached in Redis for a given driver.
type DriverCityCache interface {
	GetDriverCity(ctx context.Context, driverID string) (string, error)
	GetLastCity(ctx context.Context, driverID string) (cityID string, leftAt time.Time, err error)
	ClearLastCity(ctx context.Context, driverID string) error
}

// DriverLocationCache reads the last known location of a driver from Redis.
type DriverLocationCache interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
}

type OrderHandler struct {
	createUC          *orderuc.CreateOrderUseCase
	acceptUC          *orderuc.AcceptOrderUseCase
	updateUC          *orderuc.UpdateStatusUseCase
	cancelUC          *orderuc.CancelOrderUseCase
	finalizeUC        *orderuc.FinalizeOrderUseCase
	orderRepo         orderAccessRepository
	areas             servicearea.Repository
	gates             *driveruc.GateService
	cityCache         DriverCityCache
	locationCache     DriverLocationCache
	expansionRadius   float64
	lastCityTTL       time.Duration
	allowMockLocation bool
	isProduction      bool
}

type orderAccessRepository interface {
	orderdomain.Repository
	ListByUserID(ctx context.Context, userID string, status orderdomain.Status, limit int) ([]*orderdomain.Order, error)
	ListByDriverID(ctx context.Context, driverID string, status orderdomain.Status, limit int) ([]*orderdomain.Order, error)
	ListByStatusAndCity(ctx context.Context, status orderdomain.Status, cityID string, limit int) ([]*orderdomain.Order, error)
	ListExpandedSearching(ctx context.Context, limit int) ([]*orderdomain.Order, error)
	// GetClientBrief resolves the client's display identity (users row). It is
	// only ever attached to an order response when the caller is the order
	// owner client, the assigned driver, or an admin — never for the searching
	// pool or strangers.
	GetClientBrief(ctx context.Context, userID string) (orderdomain.ClientBrief, error)
}

func NewOrderHandler(
	createUC *orderuc.CreateOrderUseCase,
	acceptUC *orderuc.AcceptOrderUseCase,
	updateUC *orderuc.UpdateStatusUseCase,
	cancelUC *orderuc.CancelOrderUseCase,
	finalizeUC *orderuc.FinalizeOrderUseCase,
	orderRepo orderAccessRepository,
	areas servicearea.Repository,
	gates *driveruc.GateService,
	cityCache DriverCityCache,
	locationCache DriverLocationCache,
	expansionRadiusKM float64,
	lastCityTTL time.Duration,
	allowMockLocation bool,
	isProduction bool,
) *OrderHandler {
	return &OrderHandler{
		createUC:          createUC,
		acceptUC:          acceptUC,
		updateUC:          updateUC,
		cancelUC:          cancelUC,
		finalizeUC:        finalizeUC,
		orderRepo:         orderRepo,
		areas:             areas,
		gates:             gates,
		cityCache:         cityCache,
		locationCache:     locationCache,
		expansionRadius:   expansionRadiusKM,
		lastCityTTL:       lastCityTTL,
		allowMockLocation: allowMockLocation,
		isProduction:      isProduction,
	}
}

type createOrderRequest struct {
	PickupLat      float64 `json:"pickup_lat"`
	PickupLng      float64 `json:"pickup_lng"`
	DropoffLat     float64 `json:"dropoff_lat"`
	DropoffLng     float64 `json:"dropoff_lng"`
	PickupAddress  string  `json:"pickup_address"`
	DropoffAddress string  `json:"dropoff_address"`
	TowTruckType   string  `json:"tow_truck_type"`
	PaymentMethod  string  `json:"payment_method"`
	AutoDispatch   *bool   `json:"auto_dispatch"`
	IsMock         bool    `json:"is_mock"`
	Notes          string  `json:"notes"`
}

type acceptOrderRequest struct {
	DriverID string `json:"driver_id"`
}

type updateOrderStatusRequest struct {
	Status string `json:"status"`
}

type cancelOrderRequest struct {
	Reason string `json:"reason"`
}

type coordinateResponse struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type PriceBreakdown struct {
	BasePrice       int64  `json:"base_price"`
	SurchargeAmount int64  `json:"surcharge_amount"`
	SurchargeReason string `json:"surcharge_reason"`
	TotalPrice      int64  `json:"total_price"`
}

type orderResponse struct {
	ID              string             `json:"id"`
	UserID          string             `json:"user_id"`
	DriverID        *string            `json:"driver_id"`
	Pickup          coordinateResponse `json:"pickup"`
	Dropoff         coordinateResponse `json:"dropoff"`
	PickupLat       float64            `json:"pickup_lat"`
	PickupLng       float64            `json:"pickup_lng"`
	DropoffLat      float64            `json:"dropoff_lat"`
	DropoffLng      float64            `json:"dropoff_lng"`
	PickupAddress   string             `json:"pickup_address"`
	DropoffAddress  string             `json:"dropoff_address"`
	TowTruckType    string             `json:"tow_truck_type"`
	Status          string             `json:"status"`
	IsExpanded      bool               `json:"is_expanded"`
	IsCrossCity     bool               `json:"is_cross_city"`
	PriceTotal      int64              `json:"price_total"`
	SurchargeAmount int64              `json:"surcharge_amount"`
	SurchargePercent int                `json:"surcharge_percent"`
	PriceBreakdown  *PriceBreakdown    `json:"price_breakdown,omitempty"`
	DistanceKM      *float64           `json:"distance_km,omitempty"`
	CreatedAt       string             `json:"created_at"`
	UpdatedAt       string             `json:"updated_at"`
	Notes           string             `json:"notes"`
	CancelledAt     *string            `json:"cancelled_at"`
	CancelReason    string             `json:"cancel_reason,omitempty"`
	// ClientName/ClientPhone are attached only when the caller may see the
	// client's identity (order owner, assigned driver, or admin). Omitted for
	// the searching pool and for strangers, preserving client privacy.
	ClientName  string `json:"client_name,omitempty"`
	ClientPhone string `json:"client_phone,omitempty"`
}

// CreateOrder creates a new tow truck order on behalf of the authenticated client.
//
// @Summary      Create order
// @Description  Creates a tow truck order. Pickup and dropoff coordinates must be inside an active service area.
// @Tags         orders
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateOrderRequest  true  "Order payload"
// @Success      201   {object}  SingleOrderResponse
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Failure      401   {object}  ErrorResponse  "unauthorized"
// @Failure      403   {object}  ErrorResponse  "service area not allowed or wrong role"
// @Failure      500   {object}  ErrorResponse  "internal error"
// @Router       /orders [post]
func (h *OrderHandler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	var req createOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	towTruckType := orderdomain.TowTruckType(req.TowTruckType)
	if req.TowTruckType == "" {
		towTruckType = orderdomain.TowTruckWinch // default fallback
	}
	if req.PaymentMethod != "" && req.PaymentMethod != "cash" && req.PaymentMethod != "card" {
		h.writeError(w, http.StatusBadRequest, errors.New("payment_method must be cash or card"))
		return
	}
	if req.IsMock && !h.allowMockLocation {
		h.writeError(w, http.StatusBadRequest, errors.New("Обнаружено поддельное местоположение"))
		return
	}
	area, err := h.ensureServiceAreaAllows(r.Context(), req.PickupLat, req.PickupLng, req.DropoffLat, req.DropoffLng)
	if err != nil {
		if errors.Is(err, servicearea.ErrOutsideServiceArea) {
			log.Printf("WARN: service area rejected: pickup=%.6f,%.6f dropoff=%.6f,%.6f err=%v",
				req.PickupLat, req.PickupLng, req.DropoffLat, req.DropoffLng, err)
			h.writeError(w, http.StatusForbidden, errors.New("Сервис недоступен в вашем регионе"))
		} else {
			log.Printf("ERROR: service area check failed: pickup=%.6f,%.6f dropoff=%.6f,%.6f err=%v",
				req.PickupLat, req.PickupLng, req.DropoffLat, req.DropoffLng, err)
			h.writeError(w, http.StatusInternalServerError, errors.New("Internal server error"))
		}
		return
	}

	cityID := ""
	if area != nil {
		cityID = area.ID
	}

	idempotencyKey := r.Header.Get("Idempotency-Key")

	autoDispatch := true
	if req.AutoDispatch != nil {
		autoDispatch = *req.AutoDispatch
	}

	ord, err := h.createUC.Execute(r.Context(), orderuc.CreateOrderInput{
		UserID:         userID,
		PickupLat:      req.PickupLat,
		PickupLng:      req.PickupLng,
		DropoffLat:     req.DropoffLat,
		DropoffLng:     req.DropoffLng,
		PickupAddress:  req.PickupAddress,
		DropoffAddress: req.DropoffAddress,
		TowTruckType:   towTruckType,
		PaymentMethod:  req.PaymentMethod,
		AutoDispatch:   autoDispatch,
		CityID:         cityID,
		Notes:          req.Notes,
		IdempotencyKey: &idempotencyKey,
	})
	if err != nil {
		switch {
		case errors.Is(err, orderdomain.ErrValidationFailed):
			h.writeError(w, http.StatusBadRequest, err)
		case errors.Is(err, orderdomain.ErrIdempotencyConflict):
			idempotencyKey := r.Header.Get("Idempotency-Key")
			if existing, err := h.createUC.GetOrderByKey(r.Context(), idempotencyKey); err == nil && existing != nil {
				h.writeJSON(w, http.StatusCreated, map[string]any{"order": newOrderResponse(existing)})
				return
			}
			h.writeError(w, http.StatusInternalServerError, err)
		default:
			h.writeError(w, http.StatusInternalServerError, err)
		}
		return
	}

	h.writeJSON(w, http.StatusCreated, map[string]any{"order": newOrderResponse(ord)})
}

// ListOrders returns a status-filtered list of orders visible to the caller.
//
// @Summary      List orders
// @Description  Returns orders filtered by status. Clients see their own orders; drivers see searching orders or their own assigned orders; admins see all.
// @Tags         orders
// @Produce      json
// @Security     BearerAuth
// @Param        status  query     string  false  "Order status filter"  Enums(searching,accepted,arrived,in_progress,completed,cancelled)
// @Param        limit   query     int     false  "Max items (1..100, default 20)"  default(20) minimum(1) maximum(100)
// @Success      200     {object}  OrderListResponse
// @Failure      400     {object}  ErrorResponse  "invalid limit"
// @Failure      401     {object}  ErrorResponse  "unauthorized"
// @Failure      403     {object}  ErrorResponse  "forbidden role or driver gate failed"
// @Router       /orders [get]
func (h *OrderHandler) ListOrders(w http.ResponseWriter, r *http.Request) {
	status := orderdomain.Status(r.URL.Query().Get("status"))
	if status == "" {
		status = orderdomain.StatusSearching
	}

	limit := 20
	if rawLimit := r.URL.Query().Get("limit"); rawLimit != "" {
		parsed, err := strconv.Atoi(rawLimit)
		if err != nil || parsed < 1 || parsed > 100 {
			h.writeError(w, http.StatusBadRequest, errors.New("invalid limit"))
			return
		}
		limit = parsed
	}

	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var orders []*orderdomain.Order
	switch role {
	case auth.RoleAdmin:
		orders, err = h.orderRepo.ListByStatus(r.Context(), status, limit)
		if err != nil {
			h.writeError(w, http.StatusInternalServerError, err)
			return
		}
	case auth.RoleClient:
		orders, err = h.orderRepo.ListByUserID(r.Context(), userID, status, limit)
		if err != nil {
			h.writeError(w, http.StatusInternalServerError, err)
			return
		}
	case auth.RoleDriver:
		if status == orderdomain.StatusSearching {
			if h.gates != nil {
				if gateErr := h.gates.EnsureCanWork(r.Context(), userID); gateErr != nil {
					h.writeDriverGateError(w, gateErr)
					return
				}
			}
			if h.cityCache != nil {
				cityID, cityErr := h.cityCache.GetDriverCity(r.Context(), userID)
				if cityErr == nil && cityID != "" {
					orders, err = h.orderRepo.ListByStatusAndCity(r.Context(), status, cityID, limit)
					if err != nil {
						h.writeError(w, http.StatusInternalServerError, err)
						return
					}
				}
				// Append unclaimed orders from the city the driver recently left.
				lastCityID, leftAt, lcErr := h.cityCache.GetLastCity(r.Context(), userID)
				if lcErr == nil && lastCityID != "" {
					if h.lastCityTTL > 0 && time.Since(leftAt) < h.lastCityTTL {
						lastCityOrders, err := h.orderRepo.ListByStatusAndCity(r.Context(), status, lastCityID, limit)
						if err != nil {
							h.writeError(w, http.StatusInternalServerError, err)
							return
						}
						cutoff := time.Now().UTC().Add(-60 * time.Second)
						for _, o := range lastCityOrders {
							if o.CreatedAt.Before(cutoff) {
								orders = append(orders, o)
							}
						}
					} else if h.lastCityTTL > 0 {
						_ = h.cityCache.ClearLastCity(r.Context(), userID)
					}
				}
			}
			respOrders, err := h.buildDriverSearchingResponse(r.Context(), userID, orders)
			if err != nil {
				h.writeError(w, http.StatusInternalServerError, err)
				return
			}
			h.writeJSON(w, http.StatusOK, map[string]any{
				"orders": respOrders,
			})
			return
		}
		orders, err = h.orderRepo.ListByDriverID(r.Context(), userID, status, limit)
		if err != nil {
			h.writeError(w, http.StatusInternalServerError, err)
			return
		}
		payload := make([]orderResponse, 0, len(orders))
		for _, ord := range orders {
			resp := newOrderResponse(ord)
			if err := h.enrichWithClient(r.Context(), &resp, ord); err != nil {
				h.writeError(w, http.StatusInternalServerError, err)
				return
			}
			payload = append(payload, resp)
		}
		h.writeJSON(w, http.StatusOK, map[string]any{"orders": payload})
		return
	default:
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}

	payload := make([]orderResponse, 0, len(orders))
	for _, ord := range orders {
		payload = append(payload, newOrderResponse(ord))
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"orders": payload})
}

// GetOrder returns a single order by ID. Access is restricted to the owner client, the assigned driver, or an admin.
//
// @Summary      Get order by ID
// @Tags         orders
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path      string  true  "Order ID"
// @Success      200      {object}  SingleOrderResponse
// @Failure      401      {object}  ErrorResponse  "unauthorized"
// @Failure      403      {object}  ErrorResponse  "forbidden"
// @Failure      404      {object}  ErrorResponse  "order not found"
// @Router       /orders/{orderID} [get]
func (h *OrderHandler) GetOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	ord, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}
	if !h.canAccessOrder(r.Context(), ord, true) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}

	resp := newOrderResponse(ord)
	if err := h.enrichWithClient(r.Context(), &resp, ord); err != nil {
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"order": resp})
}

// GetActiveOrder returns the caller's currently active (non-terminal) order, if any.
//
// For clients: searches their own orders across searching/accepted/arrived/in_progress.
// For drivers: searches orders assigned to them across accepted/arrived/in_progress
// (searching orders are the pool, not yet assigned).
//
// @Summary      Get the caller's active order
// @Description  Returns the single non-terminal order belonging to the authenticated user, or null if there is none.
// @Tags         orders
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  SingleOrderResponse
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Router       /orders/active [get]
func (h *OrderHandler) GetActiveOrder(w http.ResponseWriter, r *http.Request) {
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var statuses []orderdomain.Status
	switch role {
	case auth.RoleClient:
		statuses = []orderdomain.Status{
			orderdomain.StatusSearching,
			orderdomain.StatusAccepted,
			orderdomain.StatusArrived,
			orderdomain.StatusInProgress,
			orderdomain.StatusAwaitingPayment,
		}
	case auth.RoleDriver:
		statuses = []orderdomain.Status{
			orderdomain.StatusAccepted,
			orderdomain.StatusArrived,
			orderdomain.StatusInProgress,
			orderdomain.StatusAwaitingPayment,
		}
	default:
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}

	for _, status := range statuses {
		var orders []*orderdomain.Order
		var listErr error
		if role == auth.RoleClient {
			orders, listErr = h.orderRepo.ListByUserID(r.Context(), userID, status, 1)
		} else {
			orders, listErr = h.orderRepo.ListByDriverID(r.Context(), userID, status, 1)
		}
		if listErr != nil {
			h.writeError(w, http.StatusInternalServerError, listErr)
			return
		}
		if len(orders) > 0 {
			resp := newOrderResponse(orders[0])
			if err := h.enrichWithClient(r.Context(), &resp, orders[0]); err != nil {
				h.writeError(w, http.StatusInternalServerError, err)
				return
			}
			h.writeJSON(w, http.StatusOK, map[string]any{"order": resp})
			return
		}
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": nil})
}

// @Summary      Accept order
// @Description  Assigns a driver to a searching order. Drivers auto-assign themselves; admins can specify a driver_id.
// @Tags         orders
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path      string              true  "Order ID"
// @Param        body     body      AcceptOrderRequest  true  "Accept payload"
// @Success      200      {object}  SingleOrderResponse
// @Failure      400      {object}  ErrorResponse  "validation failed"
// @Failure      401      {object}  ErrorResponse  "unauthorized"
// @Failure      403      {object}  ErrorResponse  "driver gate failed"
// @Failure      404      {object}  ErrorResponse  "order not found"
// @Failure      409      {object}  ErrorResponse  "order already taken or invalid transition"
// @Router       /orders/{orderID}/accept [post]
func (h *OrderHandler) AcceptOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req acceptOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}
	driverID := req.DriverID
	if role != auth.RoleAdmin {
		driverID = userID
	}
	if driverID == "" {
		h.writeError(w, http.StatusBadRequest, errors.New("driver id is required"))
		return
	}
	if role != auth.RoleAdmin && h.gates != nil {
		if gateErr := h.gates.EnsureCanWork(r.Context(), driverID); gateErr != nil {
			h.writeDriverGateError(w, gateErr)
			return
		}
	}

	ord, err := h.acceptUC.Execute(r.Context(), orderID, driverID)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	resp := newOrderResponse(ord)
	if err := h.enrichWithClient(r.Context(), &resp, ord); err != nil {
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"order": resp})
}

// @Summary      Update order status
// @Description  Advances an order through its lifecycle: accepted → arrived → in_progress → completed.
// @Tags         orders
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path      string                      true  "Order ID"
// @Param        body     body      UpdateOrderStatusRequest     true  "New status"
// @Success      200      {object}  SingleOrderResponse
// @Failure      400      {object}  ErrorResponse  "validation failed"
// @Failure      401      {object}  ErrorResponse  "unauthorized"
// @Failure      403      {object}  ErrorResponse  "forbidden"
// @Failure      404      {object}  ErrorResponse  "order not found"
// @Failure      409      {object}  ErrorResponse  "invalid status transition"
// @Router       /orders/{orderID}/status [post]
func (h *OrderHandler) UpdateOrderStatus(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	var req updateOrderStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}
	ordBefore, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}
	if !h.canAccessOrder(r.Context(), ordBefore, false) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}

	ord, err := h.updateUC.Execute(r.Context(), orderID, orderdomain.Status(req.Status))
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

// @Summary      Cancel order
// @Description  Cancels an order. Clients and drivers can cancel their own orders; admins can cancel any order.
// @Tags         orders
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path      string                true  "Order ID"
// @Param        body     body      CancelOrderRequest    true  "Cancel payload"
// @Success      200      {object}  SingleOrderResponse
// @Failure      400      {object}  ErrorResponse  "validation failed"
// @Failure      401      {object}  ErrorResponse  "unauthorized"
// @Failure      403      {object}  ErrorResponse  "forbidden"
// @Failure      404      {object}  ErrorResponse  "order not found"
// @Failure      409      {object}  ErrorResponse  "invalid transition"
// @Router       /orders/{orderID}/cancel [post]
func (h *OrderHandler) CancelOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	var req cancelOrderRequest
	if r.Body != nil {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
			h.writeError(w, http.StatusBadRequest, err)
			return
		}
	}
	ordBefore, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}
	if !h.canAccessOrder(r.Context(), ordBefore, false) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}

	ord, err := h.cancelUC.Execute(r.Context(), orderID, req.Reason)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

type finalizeOrderRequest struct {
	FinalPrice int64 `json:"final_price"`
}

// @Summary      Finalize order (driver)
// @Description  Driver completes an in-progress order and moves it to awaiting_payment. The completion total is the server-computed order price; the optional final_price body field is validated against it and never overrides it.
// @Tags         orders
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path      string                 true  "Order ID"
// @Param        body     body      FinalizeOrderRequest   true  "Final price in kopecks"
// @Success      200      {object}  SingleOrderResponse
// @Failure      400      {object}  ErrorResponse  "validation failed or final price mismatch"
// @Failure      401      {object}  ErrorResponse  "unauthorized"
// @Failure      403      {object}  ErrorResponse  "forbidden"
// @Failure      404      {object}  ErrorResponse  "order not found"
// @Failure      409      {object}  ErrorResponse  "invalid status transition"
// @Router       /orders/{orderID}/finalize [post]
func (h *OrderHandler) FinalizeOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	var req finalizeOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.FinalPrice <= 0 {
		h.writeError(w, http.StatusBadRequest, fmt.Errorf("final_price must be positive"))
		return
	}
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ord, err := h.finalizeUC.Execute(r.Context(), orderuc.FinalizeOrderInput{
		OrderID:    orderID,
		DriverID:   driverID,
		FinalPrice: req.FinalPrice,
	})
	if err != nil {
		h.writeOrderError(w, err)
		return
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

// ensureServiceAreaAllows validates both coordinates and returns the matched
// service area (determined by pickup point) so the caller can record city_id.
func (h *OrderHandler) ensureServiceAreaAllows(ctx context.Context, pickupLat, pickupLng, dropoffLat, dropoffLng float64) (*servicearea.ServiceArea, error) {
	if h.areas == nil {
		return nil, nil
	}
	area, ok, err := h.areas.CheckPoint(ctx, pickupLat, pickupLng)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("%w: pickup is outside active service areas", servicearea.ErrOutsideServiceArea)
	}
	if _, ok, err := h.areas.CheckPoint(ctx, dropoffLat, dropoffLng); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("%w: dropoff is outside active service areas", servicearea.ErrOutsideServiceArea)
	}
	return area, nil
}

// enrichWithClient attaches the client's identity (in practice their phone) to
// an order response, but only when the caller is allowed to see it: the order
// owner client, the assigned driver, or an admin. Strangers and the searching
// pool never receive it.
func (h *OrderHandler) enrichWithClient(ctx context.Context, resp *orderResponse, ord *orderdomain.Order) error {
	role, err := roleFromContext(ctx)
	if err != nil {
		return err
	}
	userID, err := userIDFromContext(ctx)
	if err != nil {
		return err
	}
	switch role {
	case auth.RoleAdmin:
		// admin sees everything
	case auth.RoleClient:
		if ord.UserID != userID {
			return nil
		}
	case auth.RoleDriver:
		// Only the assigned driver, and never while the order is still in the
		// searching pool (i.e. not yet accepted).
		if ord.DriverID == nil || *ord.DriverID != userID || ord.Status == orderdomain.StatusSearching {
			return nil
		}
	default:
		return nil
	}
	brief, err := h.orderRepo.GetClientBrief(ctx, ord.UserID)
	if err != nil {
		return err
	}
	resp.ClientName = brief.Name
	resp.ClientPhone = brief.Phone
	return nil
}

func (h *OrderHandler) canAccessOrder(ctx context.Context, ord *orderdomain.Order, allowDriverSearching bool) bool {
	role, err := roleFromContext(ctx)
	if err != nil {
		return false
	}
	userID, err := userIDFromContext(ctx)
	if err != nil {
		return false
	}
	switch role {
	case auth.RoleAdmin:
		return true
	case auth.RoleClient:
		return ord.UserID == userID
	case auth.RoleDriver:
		if ord.DriverID != nil && *ord.DriverID == userID {
			return true
		}
		return allowDriverSearching && ord.Status == orderdomain.StatusSearching
	default:
		return false
	}
}

func (h *OrderHandler) writeDriverGateError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, driveruc.ErrDriverDocumentsNotApproved),
		errors.Is(err, driveruc.ErrDriverTaxNotVerified),
		errors.Is(err, driveruc.ErrDriverSubscriptionInactive):
		h.writeError(w, http.StatusForbidden, err)
	default:
		h.writeError(w, http.StatusInternalServerError, err)
	}
}

func (h *OrderHandler) writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func (h *OrderHandler) writeError(w http.ResponseWriter, status int, err error) {
	// 5xx implies an internal/infrastructure failure: log the detail and tell
	// the client only that something broke. Domain errors (4xx) stay readable.
	if status >= http.StatusInternalServerError {
		log.Printf("ERROR: %v", err)
		h.writeJSON(w, status, map[string]string{"error": "internal error"})
		return
	}
	h.writeJSON(w, status, map[string]string{"error": err.Error()})
}

func (h *OrderHandler) writeOrderError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, orderdomain.ErrValidationFailed):
		h.writeError(w, http.StatusBadRequest, err)
	case errors.Is(err, driverdomain.ErrDriverUnavailable):
		h.writeError(w, http.StatusConflict, err)
	case errors.Is(err, orderdomain.ErrOrderNotFound):
		h.writeError(w, http.StatusNotFound, err)
	case errors.Is(err, orderdomain.ErrInvalidTransition):
		h.writeError(w, http.StatusConflict, err)
	case errors.Is(err, orderdomain.ErrOrderAlreadyTaken):
		h.writeError(w, http.StatusConflict, err)
	case errors.Is(err, orderuc.ErrCompletionRequiresFinalize):
		h.writeError(w, http.StatusBadRequest, err)
	case errors.Is(err, orderuc.ErrFinalPriceMismatch):
		h.writeError(w, http.StatusBadRequest, err)
	default:
		h.writeError(w, http.StatusInternalServerError, err)
	}
}

func newOrderResponse(ord *orderdomain.Order) orderResponse {
	var cancelledAt *string
	if ord.CancelledAt != nil {
		value := ord.CancelledAt.Format("2006-01-02T15:04:05.000Z07:00")
		cancelledAt = &value
	}

	var breakdown *PriceBreakdown
	if ord.IsCrossCity {
		base := ord.PriceTotal - ord.SurchargeAmount
		breakdown = &PriceBreakdown{
			BasePrice:       base,
			SurchargeAmount: ord.SurchargeAmount,
			SurchargeReason: "Подача из другого города",
			TotalPrice:      ord.PriceTotal,
		}
	}

	return orderResponse{
		ID:              ord.ID,
		UserID:          ord.UserID,
		DriverID:        ord.DriverID,
		Pickup: coordinateResponse{
			Lat: ord.Pickup.Lat,
			Lng: ord.Pickup.Lng,
		},
		Dropoff: coordinateResponse{
			Lat: ord.Dropoff.Lat,
			Lng: ord.Dropoff.Lng,
		},
		PickupLat:       ord.Pickup.Lat,
		PickupLng:       ord.Pickup.Lng,
		DropoffLat:      ord.Dropoff.Lat,
		DropoffLng:      ord.Dropoff.Lng,
		PickupAddress:   ord.PickupAddress,
		DropoffAddress:  ord.DropoffAddress,
		TowTruckType:    string(ord.TowTruckType),
		Status:          string(ord.Status),
		IsExpanded:      ord.IsExpanded,
		IsCrossCity:     ord.IsCrossCity,
		PriceTotal:      ord.PriceTotal,
		SurchargeAmount: ord.SurchargeAmount,
		SurchargePercent: ord.SurchargePercent,
		PriceBreakdown:  breakdown,
		CreatedAt:       ord.CreatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		UpdatedAt:       ord.UpdatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		Notes:           ord.Notes,
		CancelledAt:     cancelledAt,
		CancelReason:    ord.CancelReason,
	}
}

// buildDriverSearchingResponse merges city-scoped orders with expanded orders
// visible to the driver based on their current location.
func (h *OrderHandler) buildDriverSearchingResponse(ctx context.Context, driverUserID string, cityOrders []*orderdomain.Order) ([]orderResponse, error) {
	var driverLat, driverLng float64
	hasLocation := false
	if h.locationCache != nil {
		if loc, err := h.locationCache.GetLastLocation(ctx, driverUserID); err == nil && loc != nil {
			driverLat, driverLng = loc.Lat, loc.Lng
			hasLocation = true
		}
	}

	seen := make(map[string]struct{}, len(cityOrders))
	payload := make([]orderResponse, 0, len(cityOrders))

	for _, o := range cityOrders {
		seen[o.ID] = struct{}{}
		resp := newOrderResponse(o)
		if hasLocation {
			d := haversineKM(driverLat, driverLng, o.Pickup.Lat, o.Pickup.Lng)
			resp.DistanceKM = &d
		}
		payload = append(payload, resp)
	}

	// Append expanded orders the driver can reach but that are outside their city.
	if hasLocation && h.expansionRadius > 0 {
		expanded, err := h.orderRepo.ListExpandedSearching(ctx, 100)
		if err != nil {
			return nil, err
		}
		for _, o := range expanded {
			if _, ok := seen[o.ID]; ok {
				continue
			}
			d := haversineKM(driverLat, driverLng, o.Pickup.Lat, o.Pickup.Lng)
			if d <= h.expansionRadius {
				seen[o.ID] = struct{}{}
				resp := newOrderResponse(o)
				resp.DistanceKM = &d
				payload = append(payload, resp)
			}
		}
	}

	return payload, nil
}

// haversineKM returns the great-circle distance in kilometres between two coords.
func haversineKM(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371.0
	φ1 := lat1 * math.Pi / 180
	φ2 := lat2 * math.Pi / 180
	dφ := (lat2 - lat1) * math.Pi / 180
	dλ := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dφ/2)*math.Sin(dφ/2) +
		math.Cos(φ1)*math.Cos(φ2)*math.Sin(dλ/2)*math.Sin(dλ/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
