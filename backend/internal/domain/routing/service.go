package routing

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"

	orderdomain "evik/backend/internal/domain/order"
)

var (
	ErrRouteNotFound = errors.New("route not found")
	ErrInvalidInput  = errors.New("invalid routing input")
)

type RoutingService interface {
	CalculateRoute(ctx context.Context, req RouteRequest) (*Route, error)
	GetDirections(ctx context.Context, req RouteRequest) ([]RouteStep, error)
}

type ProMapsRoutingService struct {
	apiKey string
	client HTTPClient
}

type HTTPClient interface {
	Get(ctx context.Context, url string, headers ...map[string]string) ([]byte, error)
}

func NewProMapsRoutingService(apiKey string, client HTTPClient) *ProMapsRoutingService {
	return &ProMapsRoutingService{
		apiKey: apiKey,
		client: client,
	}
}

func (s *ProMapsRoutingService) CalculateRoute(ctx context.Context, req RouteRequest) (*Route, error) {
	if req.OrderID == "" {
		return nil, ErrInvalidInput
	}

	headers := map[string]string{}
	if s.apiKey != "" {
		headers["Authorization"] = "Bearer " + s.apiKey
	}
	response, err := s.client.Get(ctx, s.buildRouteURL(req.DriverLocation, req.ClientLocation), headers)
	if err != nil {
		return nil, err
	}

	return s.parseRouteResponse(response, req)
}

func (s *ProMapsRoutingService) GetDirections(ctx context.Context, req RouteRequest) ([]RouteStep, error) {
	route, err := s.CalculateRoute(ctx, req)
	if err != nil {
		return nil, err
	}
	return route.Steps, nil
}

func (s *ProMapsRoutingService) buildRouteURL(origin, destination orderdomain.Coordinate) string {
	values := url.Values{}
	values.Set("start", formatCoordinate(origin))
	values.Set("end", formatCoordinate(destination))
	values.Set("profile", "driving")
	return "https://api.promaps.online/routing/route?" + values.Encode()
}

func formatCoordinate(coord orderdomain.Coordinate) string {
	return fmt.Sprintf("%.6f,%.6f", coord.Lng, coord.Lat)
}

func (s *ProMapsRoutingService) parseRouteResponse(response []byte, req RouteRequest) (*Route, error) {
	var payload struct {
		Routes []struct {
			Distance float64     `json:"distance"`
			Duration float64     `json:"duration"`
			Geometry interface{} `json:"geometry"`
			Legs     []struct {
				Steps []struct {
					Instruction string      `json:"instruction"`
					Distance    float64     `json:"distance"`
					Duration    float64     `json:"duration"`
					Maneuver    interface{} `json:"maneuver"`
					Geometry    interface{} `json:"geometry"`
				} `json:"steps"`
			} `json:"legs"`
		} `json:"routes"`
	}

	if err := json.Unmarshal(response, &payload); err != nil {
		return nil, err
	}
	if len(payload.Routes) == 0 {
		return nil, ErrRouteNotFound
	}

	src := payload.Routes[0]
	route := &Route{
		OrderID:     req.OrderID,
		Origin:      req.DriverLocation,
		Destination: req.ClientLocation,
		Distance:    src.Distance,
		Duration:    int(src.Duration),
		Steps:       make([]RouteStep, 0),
		Polyline:    geometryPolyline(src.Geometry),
	}

	for _, leg := range src.Legs {
		for _, step := range leg.Steps {
			route.Steps = append(route.Steps, RouteStep{
				Instruction: step.Instruction,
				Distance:    step.Distance,
				Duration:    int(step.Duration),
				Position:    stepCoordinate(step, req.DriverLocation),
			})
		}
	}

	return route, nil
}

func geometryPolyline(geometry interface{}) string {
	if polyline, ok := geometry.(string); ok {
		return polyline
	}
	return ""
}

func stepCoordinate(step struct {
	Instruction string      `json:"instruction"`
	Distance    float64     `json:"distance"`
	Duration    float64     `json:"duration"`
	Maneuver    interface{} `json:"maneuver"`
	Geometry    interface{} `json:"geometry"`
}, fallback orderdomain.Coordinate) orderdomain.Coordinate {
	if coord, ok := coordinateFromGeometry(step.Geometry); ok {
		return coord
	}
	if maneuver, ok := step.Maneuver.(map[string]interface{}); ok {
		if raw, ok := maneuver["location"]; ok {
			if coord, ok := coordinateFromGeometry(raw); ok {
				return coord
			}
		}
	}
	return fallback
}

func coordinateFromGeometry(raw interface{}) (orderdomain.Coordinate, bool) {
	values, ok := raw.([]interface{})
	if !ok || len(values) < 2 {
		return orderdomain.Coordinate{}, false
	}

	lng, okLng := values[0].(float64)
	lat, okLat := values[1].(float64)
	if !okLng || !okLat {
		return orderdomain.Coordinate{}, false
	}

	return orderdomain.Coordinate{Lat: lat, Lng: lng}, true
}
