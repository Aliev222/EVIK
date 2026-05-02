package routing

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	orderdomain "evik/backend/internal/domain/order"
)

var (
	ErrRouteNotFound = errors.New("route not found")
	ErrInvalidInput  = errors.New("invalid routing input")
)

// RoutingService provides navigation and route calculation
type RoutingService interface {
	// CalculateRoute calculates optimal route from driver to client
	CalculateRoute(ctx context.Context, req RouteRequest) (*Route, error)

	// GetDirections gets turn-by-turn directions
	GetDirections(ctx context.Context, req RouteRequest) ([]RouteStep, error)
}

// YandexRoutingService implements routing using Yandex Maps API
type YandexRoutingService struct {
	apiKey string
	client HTTPClient
}

type HTTPClient interface {
	Get(ctx context.Context, url string) ([]byte, error)
}

func NewYandexRoutingService(apiKey string, client HTTPClient) *YandexRoutingService {
	return &YandexRoutingService{
		apiKey: apiKey,
		client: client,
	}
}

func (s *YandexRoutingService) CalculateRoute(ctx context.Context, req RouteRequest) (*Route, error) {
	if req.OrderID == "" {
		return nil, ErrInvalidInput
	}

	// Build Yandex Maps API URL for route calculation
	url := s.buildRouteURL(req.DriverLocation, req.ClientLocation)

	// Call Yandex API
	response, err := s.client.Get(ctx, url)
	if err != nil {
		return nil, err
	}

	// Parse response and build Route
	route, err := s.parseYandexRouteResponse(response, req)
	if err != nil {
		return nil, err
	}

	return route, nil
}

func (s *YandexRoutingService) GetDirections(ctx context.Context, req RouteRequest) ([]RouteStep, error) {
	route, err := s.CalculateRoute(ctx, req)
	if err != nil {
		return nil, err
	}
	return route.Steps, nil
}

func (s *YandexRoutingService) buildRouteURL(origin, destination orderdomain.Coordinate) string {
	// Yandex Maps API endpoint for route calculation
	baseURL := "https://api.routing.yandex.net/v1/routes"
	return baseURL + "?apikey=" + s.apiKey +
		"&waypoints=" + formatCoordinate(origin) + "|" + formatCoordinate(destination) +
		"&mode=driving&avoid_tolls=false&lang=ru_RU"
}

func formatCoordinate(coord orderdomain.Coordinate) string {
	return fmt.Sprintf("%.6f,%.6f", coord.Lng, coord.Lat)
}

func (s *YandexRoutingService) parseYandexRouteResponse(response []byte, req RouteRequest) (*Route, error) {
	// Parse Yandex API response JSON
	var yandexResp struct {
		Routes []struct {
			Distance float64 `json:"distance"`
			Duration int     `json:"duration"`
			Geometry struct {
				Coordinates [][]float64 `json:"coordinates"`
			} `json:"geometry"`
			Legs []struct {
				Steps []struct {
					Instruction string    `json:"instruction"`
					Distance    float64   `json:"distance"`
					Duration    int       `json:"duration"`
					Geometry    struct {
						Coordinates []float64 `json:"coordinates"`
					} `json:"geometry"`
				} `json:"steps"`
			} `json:"legs"`
		} `json:"routes"`
	}

	if err := json.Unmarshal(response, &yandexResp); err != nil {
		return nil, err
	}

	if len(yandexResp.Routes) == 0 {
		return nil, ErrRouteNotFound
	}

	yRoute := yandexResp.Routes[0]

	// Convert to internal Route format
	route := &Route{
		OrderID:     req.OrderID,
		Origin:      req.DriverLocation,
		Destination: req.ClientLocation,
		Distance:    yRoute.Distance,
		Duration:    yRoute.Duration,
		Steps:       make([]RouteStep, 0),
		Polyline:    encodePolyline(yRoute.Geometry.Coordinates),
	}

	// Convert steps
	for _, leg := range yRoute.Legs {
		for _, step := range leg.Steps {
			route.Steps = append(route.Steps, RouteStep{
				Instruction: step.Instruction,
				Distance:    step.Distance,
				Duration:    step.Duration,
				Position: orderdomain.Coordinate{
					Lat: step.Geometry.Coordinates[1],
					Lng: step.Geometry.Coordinates[0],
				},
			})
		}
	}

	return route, nil
}

func encodePolyline(coordinates [][]float64) string {
	// Simple polyline encoding - in production use proper Google Polyline algorithm
	// For now return empty string, frontend will use direct line
	return ""
}