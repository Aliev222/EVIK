package http

import (
	"encoding/json"
	"net/http"

	orderdomain "evik/backend/internal/domain/order"
	routingdomain "evik/backend/internal/domain/routing"
	"github.com/go-chi/chi/v5"
)

type RoutingHandler struct {
	routingService routingdomain.RoutingService
	orderRepo      orderdomain.Repository
}

func NewRoutingHandler(routingService routingdomain.RoutingService, orderRepo orderdomain.Repository) *RoutingHandler {
	return &RoutingHandler{
		routingService: routingService,
		orderRepo:      orderRepo,
	}
}

type calculateRouteRequest struct {
	DriverLat float64 `json:"driver_lat"`
	DriverLng float64 `json:"driver_lng"`
}

// CalculateRoute calculates route from driver to order pickup location
func (h *RoutingHandler) CalculateRoute(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	if orderID == "" {
		http.Error(w, "Order ID is required", http.StatusBadRequest)
		return
	}

	var req calculateRouteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Get order details
	order, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		if err == orderdomain.ErrOrderNotFound {
			http.Error(w, "Order not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Calculate route from driver to pickup location
	routeReq := routingdomain.RouteRequest{
		DriverLocation: orderdomain.Coordinate{Lat: req.DriverLat, Lng: req.DriverLng},
		ClientLocation: order.Pickup,
		OrderID:        orderID,
	}

	route, err := h.routingService.CalculateRoute(r.Context(), routeReq)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(route)
}

// GetDirections gets turn-by-turn directions for the driver
func (h *RoutingHandler) GetDirections(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	if orderID == "" {
		http.Error(w, "Order ID is required", http.StatusBadRequest)
		return
	}

	var req calculateRouteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Get order details
	order, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		if err == orderdomain.ErrOrderNotFound {
			http.Error(w, "Order not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Get directions from driver to pickup location
	routeReq := routingdomain.RouteRequest{
		DriverLocation: orderdomain.Coordinate{Lat: req.DriverLat, Lng: req.DriverLng},
		ClientLocation: order.Pickup,
		OrderID:        orderID,
	}

	directions, err := h.routingService.GetDirections(r.Context(), routeReq)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"order_id":   orderID,
		"directions": directions,
	})
}