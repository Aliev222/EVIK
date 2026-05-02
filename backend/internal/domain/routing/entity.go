package routing

import (
	orderdomain "evik/backend/internal/domain/order"
)

// Route represents a navigation route from driver to client
type Route struct {
	DriverID    string                     `json:"driver_id"`
	OrderID     string                     `json:"order_id"`
	Origin      orderdomain.Coordinate     `json:"origin"`
	Destination orderdomain.Coordinate     `json:"destination"`
	Distance    float64                    `json:"distance"`    // meters
	Duration    int                        `json:"duration"`    // seconds
	Steps       []RouteStep                `json:"steps"`
	Polyline    string                     `json:"polyline"`    // encoded polyline for map display
}

// RouteStep represents a single navigation instruction
type RouteStep struct {
	Instruction string                 `json:"instruction"` // Human readable instruction
	Distance    float64                `json:"distance"`    // meters for this step
	Duration    int                    `json:"duration"`    // seconds for this step
	Position    orderdomain.Coordinate `json:"position"`    // coordinate of this step
}

// RouteRequest contains parameters for route calculation
type RouteRequest struct {
	DriverLocation orderdomain.Coordinate `json:"driver_location"`
	ClientLocation orderdomain.Coordinate `json:"client_location"`
	OrderID        string                 `json:"order_id"`
}