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
)

// fakeOrderAccessRepo is a minimal orderAccessRepository for the client
// identity visibility tests. Only GetByID/GetClientBrief are behaviorful.
type fakeOrderAccessRepo struct {
	orders map[string]*orderdomain.Order
	briefs map[string]orderdomain.ClientBrief
}

func (f *fakeOrderAccessRepo) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	if f.orders == nil {
		return nil, orderdomain.ErrOrderNotFound
	}
	o := f.orders[id]
	if o == nil {
		return nil, orderdomain.ErrOrderNotFound
	}
	return o, nil
}

func (f *fakeOrderAccessRepo) GetClientBrief(_ context.Context, userID string) (orderdomain.ClientBrief, error) {
	if f.briefs != nil {
		if b, ok := f.briefs[userID]; ok {
			return b, nil
		}
	}
	return orderdomain.ClientBrief{}, nil
}

// --- orderdomain.Repository stubs ---
func (f *fakeOrderAccessRepo) Create(context.Context, *orderdomain.Order) error                               { return nil }
func (f *fakeOrderAccessRepo) Update(context.Context, *orderdomain.Order) error                               { return nil }
func (f *fakeOrderAccessRepo) UpdateStatus(context.Context, string, orderdomain.Status, time.Time) error      { return nil }
func (f *fakeOrderAccessRepo) GetByOrderKey(context.Context, string) (*orderdomain.Order, error)              { return nil, orderdomain.ErrOrderNotFound }
func (f *fakeOrderAccessRepo) AcceptOrder(context.Context, string, string) (*orderdomain.Order, error)        { return nil, nil }
func (f *fakeOrderAccessRepo) CancelOrder(context.Context, string, string, time.Time) (*orderdomain.Order, error) {
	return nil, nil
}
func (f *fakeOrderAccessRepo) ListByStatus(context.Context, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (f *fakeOrderAccessRepo) ListByUserID(context.Context, string, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (f *fakeOrderAccessRepo) ListByDriverID(context.Context, string, orderdomain.Status, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (f *fakeOrderAccessRepo) ListByStatusAndCity(context.Context, orderdomain.Status, string, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (f *fakeOrderAccessRepo) ListExpandedSearching(context.Context, int) ([]*orderdomain.Order, error) {
	return nil, nil
}
func (f *fakeOrderAccessRepo) ListAdminOrders(context.Context, orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error) {
	return nil, 0, nil
}
func (f *fakeOrderAccessRepo) GetAdminOrderDetails(context.Context, string) (*orderdomain.AdminOrderDetails, error) {
	return nil, orderdomain.ErrOrderNotFound
}

func assignedDriverOrder() *orderdomain.Order {
	driver := "driver-1"
	return &orderdomain.Order{
		ID:       "order-1",
		UserID:   "client-1",
		DriverID: &driver,
		Status:   orderdomain.StatusAccepted,
	}
}

func clientBriefRepo() *fakeOrderAccessRepo {
	return &fakeOrderAccessRepo{
		orders: map[string]*orderdomain.Order{"order-1": assignedDriverOrder()},
		briefs: map[string]orderdomain.ClientBrief{
			"client-1": {Name: "+79161234567", Phone: "+79161234567"},
		},
	}
}

// The assigned driver sees the client's phone on an accepted order.
func TestGetOrder_AssignedDriverSeesClientPhone(t *testing.T) {
	h := &OrderHandler{orderRepo: clientBriefRepo()}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1", "orderID", "order-1", "driver-1", auth.RoleDriver)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if !strings.Contains(body, "+79161234567") {
		t.Fatalf("assigned driver must see the client phone, body = %s", body)
	}
	if !strings.Contains(body, "client_phone") {
		t.Fatalf("response must expose client_phone, body = %s", body)
	}
}

// An admin sees the client's phone.
func TestGetOrder_AdminSeesClientPhone(t *testing.T) {
	h := &OrderHandler{orderRepo: clientBriefRepo()}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1", "orderID", "order-1", "admin", auth.RoleAdmin)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "+79161234567") {
		t.Fatalf("admin must see the client phone, body = %s", rec.Body.String())
	}
}

// The owning client sees their own phone.
func TestGetOrder_OwnerClientSeesOwnPhone(t *testing.T) {
	h := &OrderHandler{orderRepo: clientBriefRepo()}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1", "orderID", "order-1", "client-1", auth.RoleClient)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "+79161234567") {
		t.Fatalf("owner must see their own phone, body = %s", rec.Body.String())
	}
}

// A stranger (unassigned driver) on a non-searchable order is denied outright.
func TestGetOrder_StrangerDriverDenied(t *testing.T) {
	h := &OrderHandler{orderRepo: clientBriefRepo()}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1", "orderID", "order-1", "driver-2", auth.RoleDriver)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "+79161234567") {
		t.Fatal("stranger must not receive the client phone")
	}
}

// A stranger client cannot read the order at all.
func TestGetOrder_StrangerClientDenied(t *testing.T) {
	h := &OrderHandler{orderRepo: clientBriefRepo()}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1", "orderID", "order-1", "client-2", auth.RoleClient)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "+79161234567") {
		t.Fatal("stranger must not receive the client phone")
	}
}

// A driver inspecting a searching (not yet accepted) order sees the order but
// never the client identity — the pool is anonymous until acceptance.
func TestGetOrder_SearchingPoolDoesNotExposeClientIdentity(t *testing.T) {
	searching := &orderdomain.Order{ID: "order-2", UserID: "client-9", Status: orderdomain.StatusSearching}
	repo := &fakeOrderAccessRepo{
		orders: map[string]*orderdomain.Order{"order-2": searching},
		briefs: map[string]orderdomain.ClientBrief{
			"client-9": {Name: "+7900", Phone: "+79001234567"},
		},
	}
	h := &OrderHandler{orderRepo: repo}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-2", "orderID", "order-2", "driver-5", auth.RoleDriver)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if strings.Contains(body, "client_phone") || strings.Contains(body, "+79001234567") {
		t.Fatalf("searching pool must not expose client identity, body = %s", body)
	}
}

// A deleted client's order is shown to the assigned driver with the neutral
// marker and never a raw `deleted:` identifier.
func TestGetOrder_DeletedClientShowsNeutralMarker(t *testing.T) {
	driver := "driver-7"
	repo := &fakeOrderAccessRepo{
		orders: map[string]*orderdomain.Order{
			"order-3": {ID: "order-3", UserID: "client-3", DriverID: &driver, Status: orderdomain.StatusAccepted},
		},
		briefs: map[string]orderdomain.ClientBrief{
			// The postgres repo masks the deleted phone; the fake mirrors it.
			"client-3": {Name: "Удалённый пользователь", Phone: ""},
		},
	}
	h := &OrderHandler{orderRepo: repo}
	rec := httptest.NewRecorder()

	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-3", "orderID", "order-3", "driver-7", auth.RoleDriver)
	h.GetOrder(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Удалённый пользователь") {
		t.Fatalf("must show the neutral deleted marker, body = %s", body)
	}
	if strings.Contains(body, "deleted:") {
		t.Fatalf("must never surface a raw deleted: identifier, body = %s", body)
	}
}

// compile-time guard: fakeOrderAccessRepo must satisfy orderAccessRepository.
var _ orderAccessRepository = (*fakeOrderAccessRepo)(nil)