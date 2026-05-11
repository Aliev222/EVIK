package http

import (
	"encoding/json"
	"net/http"
	"strconv"

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

type routePreviewResponse struct {
	Points          []routePoint `json:"points"`
	DistanceMeters  float64      `json:"distanceMeters"`
	DurationSeconds int          `json:"durationSeconds"`
}

type routePoint struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
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

func (h *RoutingHandler) Preview(w http.ResponseWriter, r *http.Request) {
	fromLat, ok := parseRequiredFloatQuery(w, r, "fromLat")
	if !ok {
		return
	}
	fromLng, ok := parseRequiredFloatQuery(w, r, "fromLng")
	if !ok {
		return
	}
	toLat, ok := parseRequiredFloatQuery(w, r, "toLat")
	if !ok {
		return
	}
	toLng, ok := parseRequiredFloatQuery(w, r, "toLng")
	if !ok {
		return
	}

	route, err := h.routingService.CalculateRoute(r.Context(), routingdomain.RouteRequest{
		DriverLocation: orderdomain.Coordinate{Lat: fromLat, Lng: fromLng},
		ClientLocation: orderdomain.Coordinate{Lat: toLat, Lng: toLng},
		OrderID:        "preview",
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(routePreviewResponse{
		Points:          routePointsFromPolyline(route.Polyline),
		DistanceMeters:  route.Distance,
		DurationSeconds: route.Duration,
	})
}

func parseRequiredFloatQuery(w http.ResponseWriter, r *http.Request, key string) (float64, bool) {
	raw := r.URL.Query().Get(key)
	if raw == "" {
		http.Error(w, key+" is required", http.StatusBadRequest)
		return 0, false
	}
	value, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		http.Error(w, key+" is invalid", http.StatusBadRequest)
		return 0, false
	}
	return value, true
}

func routePointsFromPolyline(polyline string) []routePoint {
	var coords [][]float64
	if err := json.Unmarshal([]byte(polyline), &coords); err != nil {
		return []routePoint{}
	}
	points := make([]routePoint, 0, len(coords))
	for _, coord := range coords {
		if len(coord) < 2 {
			continue
		}
		points = append(points, routePoint{Lat: coord[1], Lng: coord[0]})
	}
	return points
}
