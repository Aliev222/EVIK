package http

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	admindomain "evik/backend/internal/domain/admin"
	orderdomain "evik/backend/internal/domain/order"
	"github.com/go-chi/chi/v5"
)

// fakeAdminRepo implements AdminRepository for review-privacy tests. Only the
// methods exercised by GetDriverReviews / GetOrderReview are behaviorful; the
// rest are no-op stubs required to satisfy the interface.
type fakeAdminRepo struct {
	getDriverReviewsFn func(driverID string, limit int) ([]admindomain.Review, DriverReviewsStats, error)
	getDriverRatingFn  func(driverID string) (DriverReviewsStats, error)
	getOrderReviewFn   func(orderID string) (*admindomain.Review, error)
}

func (f *fakeAdminRepo) Overview(context.Context) (admindomain.Overview, error) {
	return admindomain.Overview{}, nil
}
func (f *fakeAdminRepo) ListDriverVerifications(context.Context, int) ([]admindomain.DriverVerification, error) {
	return nil, nil
}
func (f *fakeAdminRepo) UpsertDriverVerification(context.Context, admindomain.DriverVerification) error {
	return nil
}
func (f *fakeAdminRepo) DecideDriverVerification(context.Context, admindomain.DriverVerificationDecision) error {
	return nil
}
func (f *fakeAdminRepo) ListUsers(context.Context, int) ([]admindomain.User, error) {
	return nil, nil
}
func (f *fakeAdminRepo) ListReviews(context.Context, int, int, int, string) ([]admindomain.Review, int64, error) {
	return nil, 0, nil
}
func (f *fakeAdminRepo) CreateReview(context.Context, admindomain.Review) error { return nil }
func (f *fakeAdminRepo) GetDriverReviews(_ context.Context, driverID string, limit int) ([]admindomain.Review, DriverReviewsStats, error) {
	if f.getDriverReviewsFn != nil {
		return f.getDriverReviewsFn(driverID, limit)
	}
	return nil, DriverReviewsStats{}, nil
}
func (f *fakeAdminRepo) GetDriverRating(_ context.Context, driverID string) (DriverReviewsStats, error) {
	if f.getDriverRatingFn != nil {
		return f.getDriverRatingFn(driverID)
	}
	return DriverReviewsStats{}, nil
}
func (f *fakeAdminRepo) GetOrderReview(_ context.Context, orderID string) (*admindomain.Review, error) {
	if f.getOrderReviewFn != nil {
		return f.getOrderReviewFn(orderID)
	}
	return nil, nil
}
func (f *fakeAdminRepo) HideReview(context.Context, string) error   { return nil }
func (f *fakeAdminRepo) ShowReview(context.Context, string) error   { return nil }
func (f *fakeAdminRepo) DeleteReview(context.Context, string) error { return nil }
func (f *fakeAdminRepo) ListTaxProfiles(context.Context, int) ([]AdminTaxProfile, error) {
	return nil, nil
}
func (f *fakeAdminRepo) UpdateTaxProfileStatus(context.Context, string, string, string) error {
	return nil
}
func (f *fakeAdminRepo) GetDriverDetail(context.Context, string) (*AdminDriverDetail, error) {
	return nil, nil
}
func (f *fakeAdminRepo) ListDriverOrders(context.Context, string, int, int) ([]orderdomain.AdminOrderListItem, int64, error) {
	return nil, 0, nil
}
func (f *fakeAdminRepo) ListAdminPayments(context.Context, int, int) ([]AdminListPayment, int64, error) {
	return nil, 0, nil
}
func (f *fakeAdminRepo) ListAdminWallets(context.Context, int, int, string) ([]AdminListWallet, int64, error) {
	return nil, 0, nil
}
func (f *fakeAdminRepo) ListAdminTransactions(context.Context, int, int, string, string) ([]AdminListTransaction, int64, error) {
	return nil, 0, nil
}
func (f *fakeAdminRepo) ListAdminSubscriptions(context.Context, int, int, string) ([]AdminListSubscription, int64, error) {
	return nil, 0, nil
}
func (f *fakeAdminRepo) ListAuditLog(context.Context, int, int, string, string) ([]AdminAuditLogEntry, int64, error) {
	return nil, 0, nil
}

func newAdminHandler(repo *fakeAdminRepo) *AdminHandler {
	return &AdminHandler{repo: repo}
}

// requestWithRoute builds a request whose context carries both the auth
// identity (via withAuth) and the chi route parameter expected by the handler.
func requestWithRoute(method, path, paramKey, paramValue string, userID string, role auth.Role) *http.Request {
	req := httptest.NewRequest(method, path, nil)
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add(paramKey, paramValue)
	ctx := context.WithValue(req.Context(), chi.RouteCtxKey, rctx)
	req = req.WithContext(withAuth(ctx, userID, role))
	return req
}

func sampleReview() *admindomain.Review {
	return &admindomain.Review{
		ID:         "review-1",
		OrderID:    "order-1",
		DriverID:   "driver-1",
		ClientID:   "client-1",
		DriverName: "Driver One",
		ClientName: "Client One",
		Stars:      5,
		Text:       "Превосходный водитель, всё быстро и аккуратно.",
		CreatedAt:  time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC),
	}
}

// GetDriverReviews: non-admin must receive only the aggregated rating, no
// review texts.
func TestGetDriverReviews_NonAdminGetsAggregateOnly(t *testing.T) {
	repo := &fakeAdminRepo{
		getDriverRatingFn: func(driverID string) (DriverReviewsStats, error) {
			if driverID != "driver-1" {
				t.Fatalf("driverID = %q, want driver-1", driverID)
			}
			return DriverReviewsStats{Total: 2, RatingAverage: 4.5, RatingCount: 2}, nil
		},
	}
	h := newAdminHandler(repo)
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/drivers/driver-1/reviews", "driverID", "driver-1", "client-9", auth.RoleClient)

	h.GetDriverReviews(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["rating_average"] != 4.5 {
		t.Errorf("rating_average = %v, want 4.5", body["rating_average"])
	}
	if body["rating_count"] != float64(2) {
		t.Errorf("rating_count = %v, want 2", body["rating_count"])
	}
	items, _ := body["items"].([]any)
	if len(items) != 0 {
		t.Errorf("non-admin must not receive review items, got %d", len(items))
	}
	if strings.Contains(rec.Body.String(), "Превосходный") {
		t.Error("non-admin response must not contain review text")
	}
}

// GetDriverReviews: a driver viewing another driver's reviews also gets only
// the aggregate.
func TestGetDriverReviews_DriverGetsAggregateOnly(t *testing.T) {
	repo := &fakeAdminRepo{
		getDriverRatingFn: func(string) (DriverReviewsStats, error) {
			return DriverReviewsStats{Total: 3, RatingAverage: 4.8, RatingCount: 3}, nil
		},
	}
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/drivers/driver-1/reviews", "driverID", "driver-1", "driver-7", auth.RoleDriver)

	newAdminHandler(repo).GetDriverReviews(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["rating_count"] != float64(3) {
		t.Errorf("rating_count = %v, want 3", body["rating_count"])
	}
	items, _ := body["items"].([]any)
	if len(items) != 0 {
		t.Errorf("driver must not receive other drivers' review texts, got %d", len(items))
	}
}

// GetDriverReviews: admin keeps the full list including texts.
func TestGetDriverReviews_AdminGetsFullListWithTexts(t *testing.T) {
	repo := &fakeAdminRepo{
		getDriverReviewsFn: func(driverID string, limit int) ([]admindomain.Review, DriverReviewsStats, error) {
			return []admindomain.Review{*sampleReview()}, DriverReviewsStats{Total: 1, RatingAverage: 5, RatingCount: 1}, nil
		},
	}
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/drivers/driver-1/reviews", "driverID", "driver-1", "admin", auth.RoleAdmin)

	newAdminHandler(repo).GetDriverReviews(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Превосходный") {
		t.Error("admin response must include the review text")
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("items = %d, want 1", len(items))
	}
}

// GetOrderReview: the authoring client sees the review.
func TestGetOrderReview_AuthoringClientSeesReview(t *testing.T) {
	repo := &fakeAdminRepo{getOrderReviewFn: func(orderID string) (*admindomain.Review, error) {
		return sampleReview(), nil
	}}
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1/review", "orderID", "order-1", "client-1", auth.RoleClient)

	newAdminHandler(repo).GetOrderReview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Превосходный") {
		t.Error("participant must see the review text")
	}
}

// GetOrderReview: the order's driver sees the review.
func TestGetOrderReview_OrderDriverSeesReview(t *testing.T) {
	repo := &fakeAdminRepo{getOrderReviewFn: func(orderID string) (*admindomain.Review, error) {
		return sampleReview(), nil
	}}
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1/review", "orderID", "order-1", "driver-1", auth.RoleDriver)

	newAdminHandler(repo).GetOrderReview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Превосходный") {
		t.Error("order driver must see the review text")
	}
}

// GetOrderReview: a stranger (authorized client, not a participant) is denied
// and never sees the text.
func TestGetOrderReview_StrangerDenied(t *testing.T) {
	repo := &fakeAdminRepo{getOrderReviewFn: func(orderID string) (*admindomain.Review, error) {
		return sampleReview(), nil
	}}
	for _, tc := range []struct {
		name   string
		userID string
		role   auth.Role
	}{
		{name: "other client", userID: "client-2", role: auth.RoleClient},
		{name: "other driver", userID: "driver-9", role: auth.RoleDriver},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1/review", "orderID", "order-1", tc.userID, tc.role)
			newAdminHandler(repo).GetOrderReview(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
			}
			if strings.Contains(rec.Body.String(), "Превосходный") {
				t.Error("stranger must not receive the review text")
			}
		})
	}
}

// GetOrderReview: admin sees the review regardless of participation.
func TestGetOrderReview_AdminSeesReview(t *testing.T) {
	repo := &fakeAdminRepo{getOrderReviewFn: func(orderID string) (*admindomain.Review, error) {
		return sampleReview(), nil
	}}
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1/review", "orderID", "order-1", "admin", auth.RoleAdmin)

	newAdminHandler(repo).GetOrderReview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Превосходный") {
		t.Error("admin must see the review text")
	}
}

// GetOrderReview: a missing review is a 404, not a 500 — for any caller.
func TestGetOrderReview_MissingReviewIs404(t *testing.T) {
	repo := &fakeAdminRepo{getOrderReviewFn: func(orderID string) (*admindomain.Review, error) {
		return nil, nil
	}}
	for _, tc := range []struct {
		name   string
		userID string
		role   auth.Role
	}{
		{name: "stranger", userID: "client-2", role: auth.RoleClient},
		{name: "participant", userID: "client-1", role: auth.RoleClient},
		{name: "admin", userID: "admin", role: auth.RoleAdmin},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-1/review", "orderID", "order-1", tc.userID, tc.role)
			newAdminHandler(repo).GetOrderReview(rec, req)

			if rec.Code != http.StatusNotFound {
				t.Fatalf("status = %d, want 404 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}
