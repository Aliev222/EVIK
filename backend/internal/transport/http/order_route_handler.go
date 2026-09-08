package http

import (
	"encoding/json"
	"errors"
	orderuc "evik/backend/internal/usecase/order"
	"github.com/go-chi/chi/v5"
	"net/http"
)

func (h *OrderHandler) QuoteOrderRoute(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, 401, "unauthorized")
		return
	}
	if h.RouteChanges == nil {
		h.writeError(w, 503, errors.New("Изменение маршрута временно недоступно"))
		return
	}
	var d orderuc.RouteDraft
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&d); err != nil {
		h.writeError(w, 400, errors.New("Некорректный маршрут"))
		return
	}
	ord, err := h.orderRepo.GetByID(r.Context(), chi.URLParam(r, "orderID"))
	if err != nil || ord.UserID != userID {
		h.writeError(w, 404, errors.New("Заказ не найден"))
		return
	}
	if err = orderuc.ValidateRouteDraft(ord, d); err != nil {
		h.writeError(w, 409, err)
		return
	}
	if _, err = h.ensureServiceAreaAllows(r.Context(), d.PickupLat, d.PickupLng, d.DropoffLat, d.DropoffLng); err != nil {
		h.writeError(w, 400, errors.New("Адрес вне зоны обслуживания"))
		return
	}
	q, err := h.RouteChanges.Quote(r.Context(), userID, ord.ID, d)
	if err != nil {
		h.writeError(w, 409, err)
		return
	}
	h.writeJSON(w, 200, q)
}
func (h *OrderHandler) ConfirmOrderRoute(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, 401, "unauthorized")
		return
	}
	if h.RouteChanges == nil {
		h.writeError(w, 503, errors.New("Изменение маршрута временно недоступно"))
		return
	}
	var req struct {
		QuoteID string `json:"quote_id"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&req); err != nil || req.QuoteID == "" {
		h.writeError(w, 400, errors.New("Нужен расчёт стоимости"))
		return
	}
	ord, err := h.RouteChanges.Confirm(r.Context(), userID, chi.URLParam(r, "orderID"), req.QuoteID)
	if err != nil {
		h.writeError(w, 409, err)
		return
	}
	h.writeJSON(w, 200, map[string]any{"order": newOrderResponse(ord)})
}
