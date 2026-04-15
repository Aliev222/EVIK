package http

import (
	"encoding/json"
	"errors"
	"net/http"

	orderdomain "evik/backend/internal/domain/order"
	orderuc "evik/backend/internal/usecase/order"
)

type OrderHandler struct {
	createUC *orderuc.CreateOrderUseCase
	cancelUC *orderuc.CancelOrderUseCase
}

func NewOrderHandler(createUC *orderuc.CreateOrderUseCase, cancelUC *orderuc.CancelOrderUseCase) *OrderHandler {
	return &OrderHandler{createUC: createUC, cancelUC: cancelUC}
}

type createOrderRequest struct {
	UserID       string  `json:"user_id"`
	PickupLat    float64 `json:"pickup_lat"`
	PickupLng    float64 `json:"pickup_lng"`
	DropoffLat   float64 `json:"dropoff_lat"`
	DropoffLng   float64 `json:"dropoff_lng"`
	AutoDispatch bool    `json:"auto_dispatch"`
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

	h.writeJSON(w, http.StatusCreated, map[string]any{"order": ord})
}

func (h *OrderHandler) writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func (h *OrderHandler) writeError(w http.ResponseWriter, status int, err error) {
	h.writeJSON(w, status, map[string]string{"error": err.Error()})
}
