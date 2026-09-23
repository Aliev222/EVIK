package http

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"evik/backend/internal/auth"
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

type orderRouteResponse struct {
	*routingdomain.Route
	Points          []routePoint `json:"points"`
	DistanceMeters  float64      `json:"distanceMeters"`
	DurationSeconds int          `json:"durationSeconds"`
	RouteVersion    string       `json:"routeVersion"`
	Phase           string       `json:"phase"`
	Target          string       `json:"target"`
}

type routePoint struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// @Summary      Calculate route to pickup
// @Description  Calculates the optimal driving route from the driver's current location to the order's pickup point.
// @Tags         routing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string                  true  "Order ID"
// @Param        body     body  CalculateRouteRequest   true  "Driver location"
// @Success      200  {object}  map[string]any  "route with polyline, distance, duration"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Failure      404  {object}  ErrorResponse  "order not found"
// @Router       /routing/orders/{orderID}/route [post]
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
		writeInternalError(w, err)
		return
	}
	callerID, idErr := userIDFromContext(r.Context())
	callerRole, roleErr := roleFromContext(r.Context())
	if idErr != nil || roleErr != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !canAccessOrderRoute(order, callerID, callerRole) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	if isTerminalRouteStatus(order.Status) {
		http.Error(w, "order is closed", http.StatusConflict)
		return
	}

	target, phase, targetName := routeTarget(order)

	routeReq := routingdomain.RouteRequest{
		DriverLocation: orderdomain.Coordinate{Lat: req.DriverLat, Lng: req.DriverLng},
		ClientLocation: target,
		OrderID:        orderID,
	}

	route, err := h.routingService.CalculateRoute(r.Context(), routeReq)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(orderRouteResponse{
		Route:           route,
		Points:          routePointsFromPolyline(route.Polyline),
		DistanceMeters:  route.Distance,
		DurationSeconds: route.Duration,
		RouteVersion:    canonicalRouteVersion(order, route.Polyline, phase, targetName),
		Phase:           phase,
		Target:          targetName,
	})
}

func canonicalRouteVersion(order *orderdomain.Order, polyline, phase, target string) string {
	payload := fmt.Sprintf("%s\x00%s\x00%s\x00%s\x00%s", order.ID, order.UpdatedAt.UTC().Format(time.RFC3339Nano), phase, target, polyline)
	digest := sha256.Sum256([]byte(payload))
	return fmt.Sprintf("%x", digest[:12])
}

func canAccessOrderRoute(order *orderdomain.Order, callerID string, role auth.Role) bool {
	if role == auth.RoleAdmin {
		return true
	}
	if role == auth.RoleClient {
		return order.UserID == callerID
	}
	return role == auth.RoleDriver && order.DriverID != nil && *order.DriverID == callerID
}

func isTerminalRouteStatus(status orderdomain.Status) bool {
	return status == orderdomain.StatusCompleted || status == orderdomain.StatusCancelled || status == orderdomain.StatusNoDriverFound
}

func routeTarget(order *orderdomain.Order) (orderdomain.Coordinate, string, string) {
	if order.Status == orderdomain.StatusInProgress || order.Status == orderdomain.StatusAwaitingPayment {
		return order.Dropoff, "to_destination", "dropoff"
	}
	return order.Pickup, "to_pickup", "pickup"
}

// @Summary      Get turn-by-turn directions
// @Description  Returns turn-by-turn driving directions from the driver's location to the order's pickup point.
// @Tags         routing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string                  true  "Order ID"
// @Param        body     body  CalculateRouteRequest   true  "Driver location"
// @Success      200  {object}  map[string]any  "directions with order_id"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Failure      404  {object}  ErrorResponse  "order not found"
// @Router       /routing/orders/{orderID}/directions [post]
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
		writeInternalError(w, err)
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
		writeInternalError(w, err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"order_id":   orderID,
		"directions": directions,
	})
}

// @Summary      Preview route
// @Description  Returns a route preview between two coordinates without requiring an order. Used for map display.
// @Tags         routing
// @Produce      json
// @Security     BearerAuth
// @Param        fromLat  query  number  true  "Start latitude"
// @Param        fromLng  query  number  true  "Start longitude"
// @Param        toLat    query  number  true  "End latitude"
// @Param        toLng    query  number  true  "End longitude"
// @Success      200  {object}  routePreviewResponse  "route preview with points, distance, duration"
// @Failure      400  {object}  ErrorResponse  "missing or invalid parameters"
// @Router       /routing/preview [get]
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
		writeUpstreamError(w, http.StatusBadGateway, err)
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
