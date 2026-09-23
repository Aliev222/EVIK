package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	orderdomain "evik/backend/internal/domain/order"
	routingdomain "evik/backend/internal/domain/routing"
	"github.com/go-chi/chi/v5"
)

type routeOrderRepo struct {
	orderdomain.Repository
	order *orderdomain.Order
}

func (r *routeOrderRepo) GetByID(context.Context, string) (*orderdomain.Order, error) {
	return r.order, nil
}

type routeServiceStub struct {
	request routingdomain.RouteRequest
	route   *routingdomain.Route
}

func (s *routeServiceStub) CalculateRoute(_ context.Context, request routingdomain.RouteRequest) (*routingdomain.Route, error) {
	s.request = request
	return s.route, nil
}

func (s *routeServiceStub) GetDirections(context.Context, routingdomain.RouteRequest) ([]routingdomain.RouteStep, error) {
	return nil, nil
}

func TestCalculateRouteUsesPhaseTargetAndReturnsCanonicalMetadata(t *testing.T) {
	driverID := "driver-1"
	order := &orderdomain.Order{
		ID:        "order-1",
		UserID:    "client-1",
		DriverID:  &driverID,
		Pickup:    orderdomain.Coordinate{Lat: 42.98, Lng: 47.50},
		Dropoff:   orderdomain.Coordinate{Lat: 43.01, Lng: 47.53},
		Status:    orderdomain.StatusInProgress,
		UpdatedAt: time.Date(2026, 9, 18, 12, 0, 0, 0, time.UTC),
	}
	service := &routeServiceStub{route: &routingdomain.Route{
		Polyline: `[[47.5,42.98],[47.53,43.01]]`,
		Distance: 4200,
		Duration: 600,
	}}
	handler := NewRoutingHandler(service, &routeOrderRepo{order: order})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/routing/orders/order-1/route", strings.NewReader(`{"driver_lat":42.99,"driver_lng":47.51}`))
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("orderID", order.ID)
	req = req.WithContext(context.WithValue(withAuth(req.Context(), order.UserID, auth.RoleClient), chi.RouteCtxKey, rctx))
	res := httptest.NewRecorder()

	handler.CalculateRoute(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
	if service.request.ClientLocation != order.Dropoff {
		t.Fatalf("target=%+v want dropoff=%+v", service.request.ClientLocation, order.Dropoff)
	}
	body := res.Body.String()
	for _, expected := range []string{`"phase":"to_destination"`, `"target":"dropoff"`, `"routeVersion":"`, `"points":[`} {
		if !strings.Contains(body, expected) {
			t.Fatalf("response missing %s: %s", expected, body)
		}
	}
}

func TestCalculateRouteRejectsUnrelatedClient(t *testing.T) {
	order := &orderdomain.Order{ID: "order-1", UserID: "client-1", Status: orderdomain.StatusAccepted}
	handler := NewRoutingHandler(&routeServiceStub{}, &routeOrderRepo{order: order})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/routing/orders/order-1/route", strings.NewReader(`{"driver_lat":42.99,"driver_lng":47.51}`))
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("orderID", order.ID)
	req = req.WithContext(context.WithValue(withAuth(req.Context(), "client-2", auth.RoleClient), chi.RouteCtxKey, rctx))
	res := httptest.NewRecorder()

	handler.CalculateRoute(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
}

func TestCanonicalRouteVersionIsStableAndChangesWithPhaseOrGeometry(t *testing.T) {
	order := &orderdomain.Order{ID: "order-1", UpdatedAt: time.Date(2026, 9, 18, 12, 0, 0, 0, time.UTC)}
	first := canonicalRouteVersion(order, `[[47.5,42.98],[47.51,42.99]]`, "to_pickup", "pickup")
	if again := canonicalRouteVersion(order, `[[47.5,42.98],[47.51,42.99]]`, "to_pickup", "pickup"); again != first {
		t.Fatalf("same canonical route changed version: %q != %q", again, first)
	}
	if changed := canonicalRouteVersion(order, `[[47.5,42.98],[47.51,42.99]]`, "to_destination", "dropoff"); changed == first {
		t.Fatal("phase/target change must change route version")
	}
	if changed := canonicalRouteVersion(order, `[[47.5,42.98],[47.52,43.00]]`, "to_pickup", "pickup"); changed == first {
		t.Fatal("geometry change must change route version")
	}
}
