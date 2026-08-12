package http

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"evik/backend/internal/auth"
	admindomain "evik/backend/internal/domain/admin"
	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
)

// Criterion: an internal/DB error raised inside a handler must produce a
// generic 500 with the detail only in the server log — never the raw error
// text. Domain/validation errors (4xx) must stay readable.

func TestGetDriverReviews_DBErrorIsGeneric500(t *testing.T) {
	repo := &fakeAdminRepo{
		getDriverReviewsFn: func(string, int) ([]admindomain.Review, DriverReviewsStats, error) {
			return nil, DriverReviewsStats{}, errors.New(`pq: relation "driver_reviews" does not exist`)
		},
	}
	h := newAdminHandler(repo)
	req := requestWithRoute(http.MethodGet, "/drivers/driver-1/reviews", "driverID", "driver-1", "admin-1", auth.RoleAdmin)
	rec := httptest.NewRecorder()
	h.GetDriverReviews(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "pq:") {
		t.Fatalf("body = %q, raw DB error leaked to client", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "internal error") {
		t.Fatalf("body = %q, want generic internal error", rec.Body.String())
	}
}

func TestGetOrderReview_DBErrorIsGeneric500(t *testing.T) {
	repo := &fakeAdminRepo{
		getOrderReviewFn: func(string) (*admindomain.Review, error) {
			return nil, errors.New("connection reset by peer")
		},
	}
	h := newAdminHandler(repo)
	req := requestWithRoute(http.MethodGet, "/orders/order-1/review", "orderID", "order-1", "client-1", auth.RoleClient)
	rec := httptest.NewRecorder()
	h.GetOrderReview(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "connection reset") {
		t.Fatalf("body = %q, raw infra error leaked to client", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "internal error") {
		t.Fatalf("body = %q, want generic internal error", rec.Body.String())
	}
}

func TestGetDriverReviews_NonAdminRatingDBErrorIsGeneric500(t *testing.T) {
	repo := &fakeAdminRepo{
		getDriverRatingFn: func(string) (DriverReviewsStats, error) {
			return DriverReviewsStats{}, errors.New("pq: FATAL: remaining connection slots are reserved")
		},
	}
	h := newAdminHandler(repo)
	req := requestWithRoute(http.MethodGet, "/drivers/driver-1/reviews", "driverID", "driver-1", "client-1", auth.RoleClient)
	rec := httptest.NewRecorder()
	h.GetDriverReviews(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "pq:") {
		t.Fatalf("body = %q, raw DB error leaked to client", rec.Body.String())
	}
}

func TestOrderHandlerWriteError_Hides5xxKeeps4xx(t *testing.T) {
	h := &OrderHandler{}
	rec := httptest.NewRecorder()
	h.writeError(rec, http.StatusInternalServerError, errors.New("sql: table orders does not exist"))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "sql:") {
		t.Fatalf("body = %q, raw SQL error leaked", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "internal error") {
		t.Fatalf("body = %q, want generic message", rec.Body.String())
	}

	// 4xx domain errors stay readable.
	rec2 := httptest.NewRecorder()
	h.writeError(rec2, http.StatusConflict, orderdomain.ErrInvalidTransition)
	if rec2.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec2.Code)
	}
	if !strings.Contains(rec2.Body.String(), orderdomain.ErrInvalidTransition.Error()) {
		t.Fatalf("body = %q, domain message must stay readable", rec2.Body.String())
	}
}

func TestDriverHandlerWriteError_Hides5xxKeeps4xx(t *testing.T) {
	h := &DriverHandler{}
	rec := httptest.NewRecorder()
	h.writeError(rec, http.StatusInternalServerError, errors.New("dial tcp: i/o timeout"))
	if strings.Contains(rec.Body.String(), "i/o timeout") {
		t.Fatalf("body = %q, raw infra error leaked", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "internal error") {
		t.Fatalf("body = %q, want generic message", rec.Body.String())
	}

	rec2 := httptest.NewRecorder()
	h.writeError(rec2, http.StatusNotFound, driverdomain.ErrDriverNotFound)
	if !strings.Contains(rec2.Body.String(), driverdomain.ErrDriverNotFound.Error()) {
		t.Fatalf("body = %q, domain message must stay readable", rec2.Body.String())
	}
}

func TestWriteInternalErrorHelper(t *testing.T) {
	rec := httptest.NewRecorder()
	writeInternalError(rec, errors.New("pq: deadlock detected"))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "deadlock") {
		t.Fatalf("body = %q, raw detail leaked", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "internal error") {
		t.Fatalf("body = %q, want generic message", rec.Body.String())
	}
}

func TestWriteUpstreamErrorHelper(t *testing.T) {
	rec := httptest.NewRecorder()
	writeUpstreamError(rec, http.StatusBadGateway, errors.New("nominatim 503 upstream"))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "nominatim") {
		t.Fatalf("body = %q, raw upstream detail leaked", rec.Body.String())
	}
}
