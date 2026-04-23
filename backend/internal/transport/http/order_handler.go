package http

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
	orderuc "evik/backend/internal/usecase/order"
	"github.com/go-chi/chi/v5"
)

type OrderHandler struct {
	createUC  *orderuc.CreateOrderUseCase
	acceptUC  *orderuc.AcceptOrderUseCase
	updateUC  *orderuc.UpdateStatusUseCase
	cancelUC  *orderuc.CancelOrderUseCase
	orderRepo orderdomain.Repository
}

func NewOrderHandler(
	createUC *orderuc.CreateOrderUseCase,
	acceptUC *orderuc.AcceptOrderUseCase,
	updateUC *orderuc.UpdateStatusUseCase,
	cancelUC *orderuc.CancelOrderUseCase,
	orderRepo orderdomain.Repository,
) *OrderHandler {
	return &OrderHandler{
		createUC:  createUC,
		acceptUC:  acceptUC,
		updateUC:  updateUC,
		cancelUC:  cancelUC,
		orderRepo: orderRepo,
	}
}

type createOrderRequest struct {
	UserID       string  `json:"user_id"`
	PickupLat    float64 `json:"pickup_lat"`
	PickupLng    float64 `json:"pickup_lng"`
	DropoffLat   float64 `json:"dropoff_lat"`
	DropoffLng   float64 `json:"dropoff_lng"`
	AutoDispatch bool    `json:"auto_dispatch"`
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

type orderResponse struct {
	ID          string             `json:"id"`
	UserID      string             `json:"user_id"`
	DriverID    *string            `json:"driver_id"`
	Pickup      coordinateResponse `json:"pickup"`
	Dropoff     coordinateResponse `json:"dropoff"`
	PickupLat   float64            `json:"pickup_lat"`
	PickupLng   float64            `json:"pickup_lng"`
	DropoffLat  float64            `json:"dropoff_lat"`
	DropoffLng  float64            `json:"dropoff_lng"`
	Status      string             `json:"status"`
	CreatedAt   string             `json:"created_at"`
	UpdatedAt   string             `json:"updated_at"`
	CancelledAt *string            `json:"cancelled_at"`
}

func (h *OrderHandler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	var req createOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}

	ord, err := h.createUC.Execute(r.Context(), orderuc.CreateOrderInput{
		UserID:       req.UserID,
		PickupLat:    req.PickupLat,
		PickupLng:    req.PickupLng,
		DropoffLat:   req.DropoffLat,
		DropoffLng:   req.DropoffLng,
		AutoDispatch: req.AutoDispatch,
	})
	if err != nil {
		switch {
		case errors.Is(err, orderdomain.ErrValidationFailed):
			h.writeError(w, http.StatusBadRequest, err)
		default:
			h.writeError(w, http.StatusInternalServerError, err)
		}
		return
	}

	h.writeJSON(w, http.StatusCreated, map[string]any{"order": newOrderResponse(ord)})
}

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

	orders, err := h.orderRepo.ListByStatus(r.Context(), status, limit)
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, err)
		return
	}

	payload := make([]orderResponse, 0, len(orders))
	for _, ord := range orders {
		payload = append(payload, newOrderResponse(ord))
	}
	h.writeJSON(w, http.StatusOK, map[string]any{"orders": payload})
}

func (h *OrderHandler) GetOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	ord, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

func (h *OrderHandler) AcceptOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	var req acceptOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}

	ord, err := h.acceptUC.Execute(r.Context(), orderID, req.DriverID)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

func (h *OrderHandler) UpdateOrderStatus(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	var req updateOrderStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, err)
		return
	}

	ord, err := h.updateUC.Execute(r.Context(), orderID, orderdomain.Status(req.Status))
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

func (h *OrderHandler) CancelOrder(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	var req cancelOrderRequest
	if r.Body != nil {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
			h.writeError(w, http.StatusBadRequest, err)
			return
		}
	}

	ord, err := h.cancelUC.Execute(r.Context(), orderID, req.Reason)
	if err != nil {
		h.writeOrderError(w, err)
		return
	}

	h.writeJSON(w, http.StatusOK, map[string]any{"order": newOrderResponse(ord)})
}

func (h *OrderHandler) writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func (h *OrderHandler) writeError(w http.ResponseWriter, status int, err error) {
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

	return orderResponse{
		ID:       ord.ID,
		UserID:   ord.UserID,
		DriverID: ord.DriverID,
		Pickup: coordinateResponse{
			Lat: ord.Pickup.Lat,
			Lng: ord.Pickup.Lng,
		},
		Dropoff: coordinateResponse{
			Lat: ord.Dropoff.Lat,
			Lng: ord.Dropoff.Lng,
		},
		PickupLat:   ord.Pickup.Lat,
		PickupLng:   ord.Pickup.Lng,
		DropoffLat:  ord.Dropoff.Lat,
		DropoffLng:  ord.Dropoff.Lng,
		Status:      string(ord.Status),
		CreatedAt:   ord.CreatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		UpdatedAt:   ord.UpdatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		CancelledAt: cancelledAt,
	}
}
