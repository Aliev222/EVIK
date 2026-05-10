package routing

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"

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

type OSRMRoutingService struct {
	baseURL string
	client  HTTPClient
}

type HTTPClient interface {
	Get(ctx context.Context, url string, headers ...map[string]string) ([]byte, error)
}

func NewOSRMRoutingService(baseURL string, client HTTPClient) *OSRMRoutingService {
	if strings.TrimSpace(baseURL) == "" {
		baseURL = "https://router.project-osrm.org"
	}
	return &OSRMRoutingService{
		baseURL: strings.TrimRight(baseURL, "/"),
		client:  client,
	}
}

func (s *OSRMRoutingService) CalculateRoute(ctx context.Context, req RouteRequest) (*Route, error) {
	if req.OrderID == "" {
		return nil, ErrInvalidInput
	}

	response, err := s.client.Get(ctx, s.buildRouteURL(req.DriverLocation, req.ClientLocation))
	if err != nil {
		return nil, err
	}

	return s.parseRouteResponse(response, req)
}

func (s *OSRMRoutingService) GetDirections(ctx context.Context, req RouteRequest) ([]RouteStep, error) {
	route, err := s.CalculateRoute(ctx, req)
	if err != nil {
		return nil, err
	}
	return route.Steps, nil
}

func (s *OSRMRoutingService) buildRouteURL(origin, destination orderdomain.Coordinate) string {
	values := url.Values{}
	values.Set("overview", "full")
	values.Set("geometries", "geojson")
	values.Set("steps", "true")
	return fmt.Sprintf(
		"%s/route/v1/car/%s;%s?%s",
		s.baseURL,
		formatCoordinate(origin),
		formatCoordinate(destination),
		values.Encode(),
	)
}

func formatCoordinate(coord orderdomain.Coordinate) string {
	return fmt.Sprintf("%.6f,%.6f", coord.Lng, coord.Lat)
}

func (s *OSRMRoutingService) parseRouteResponse(response []byte, req RouteRequest) (*Route, error) {
	var payload struct {
		Code   string `json:"code"`
		Routes []struct {
			Distance float64 `json:"distance"`
			Duration float64 `json:"duration"`
			Geometry struct {
				Coordinates [][]float64 `json:"coordinates"`
			} `json:"geometry"`
			Legs []struct {
				Steps []struct {
					Distance float64 `json:"distance"`
					Duration float64 `json:"duration"`
					Maneuver struct {
						Type     string    `json:"type"`
						Modifier string    `json:"modifier"`
						Location []float64 `json:"location"`
					} `json:"maneuver"`
				} `json:"steps"`
			} `json:"legs"`
		} `json:"routes"`
	}

	if err := json.Unmarshal(response, &payload); err != nil {
		return nil, err
	}
	if payload.Code != "" && payload.Code != "Ok" {
		return nil, ErrRouteNotFound
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
		Polyline:    geometryPolyline(src.Geometry.Coordinates),
	}

	for _, leg := range src.Legs {
		for _, step := range leg.Steps {
			route.Steps = append(route.Steps, RouteStep{
				Instruction: osrmInstruction(step.Maneuver.Type, step.Maneuver.Modifier),
				Distance:    step.Distance,
				Duration:    int(step.Duration),
				Position:    coordinateFromLonLat(step.Maneuver.Location, req.DriverLocation),
			})
		}
	}

	return route, nil
}

func geometryPolyline(coordinates [][]float64) string {
	raw, err := json.Marshal(coordinates)
	if err != nil {
		return ""
	}
	return string(raw)
}

func coordinateFromLonLat(values []float64, fallback orderdomain.Coordinate) orderdomain.Coordinate {
	if len(values) < 2 {
		return fallback
	}
	return orderdomain.Coordinate{Lat: values[1], Lng: values[0]}
}

func osrmInstruction(kind, modifier string) string {
	if modifier == "" {
		return kind
	}
	return kind + " " + modifier
}
