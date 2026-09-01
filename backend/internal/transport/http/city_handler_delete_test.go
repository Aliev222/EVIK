package http

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	servicearea "evik/backend/internal/domain/servicearea"
	"github.com/go-chi/chi/v5"
)

// fakeAreaRepo is a minimal servicearea.Repository for testing CityHandler
// Delete semantics. Only Delete is behaviorful; the rest are no-ops.
type fakeAreaRepo struct {
	deleteFn func(ctx context.Context, id string) error
}

func (f *fakeAreaRepo) CheckPoint(context.Context, float64, float64) (*servicearea.ServiceArea, bool, error) {
	return nil, false, nil
}
func (f *fakeAreaRepo) List(context.Context) ([]servicearea.ServiceArea, error) { return nil, nil }
func (f *fakeAreaRepo) GetByID(context.Context, string) (*servicearea.ServiceArea, error) {
	return nil, nil
}
func (f *fakeAreaRepo) Create(context.Context, servicearea.ServiceArea) error { return nil }
func (f *fakeAreaRepo) Update(context.Context, servicearea.ServiceArea) error { return nil }
func (f *fakeAreaRepo) SetActive(context.Context, string, bool) error         { return nil }
func (f *fakeAreaRepo) Delete(ctx context.Context, id string) error {
	if f.deleteFn != nil {
		return f.deleteFn(ctx, id)
	}
	return nil
}
func (f *fakeAreaRepo) ExistsBySlug(context.Context, string) (bool, error) { return false, nil }
func (f *fakeAreaRepo) ExistsByName(context.Context, string) (bool, error) { return false, nil }

func cityDeleteRequest(areaID string) *http.Request {
	req := httptest.NewRequest(http.MethodDelete, "/admin/cities/"+areaID, nil)
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("id", areaID)
	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

// Deleting an area that is referenced by orders (FK) must surface as a clean
// 409 Conflict with a readable message, not a raw 500.
func TestCityDelete_AreaInUseReturns409(t *testing.T) {
	repo := &fakeAreaRepo{deleteFn: func(context.Context, string) error { return servicearea.ErrAreaInUse }}
	h := NewCityHandler(repo, nil, nil)
	rec := httptest.NewRecorder()
	h.Delete(rec, cityDeleteRequest("area-1"))

	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409 Conflict", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "in use") {
		t.Fatalf("body = %q, want readable conflict message", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "SQLSTATE") || strings.Contains(rec.Body.String(), "constraint") {
		t.Fatalf("body = %q, raw DB detail leaked", rec.Body.String())
	}
}

// A free (unused) area deletes successfully.
func TestCityDelete_FreeAreaReturnsOK(t *testing.T) {
	repo := &fakeAreaRepo{deleteFn: func(context.Context, string) error { return nil }}
	h := NewCityHandler(repo, nil, nil)
	rec := httptest.NewRecorder()
	h.Delete(rec, cityDeleteRequest("area-free"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}

// Deleting a city succeeds even when orders reference it (FK SET NULL keeps
// orders running); no more 409 for active orders.
func TestCityDelete_SucceedsWithOrders(t *testing.T) {
	repo := &fakeAreaRepo{deleteFn: func(context.Context, string) error { return nil }}
	h := NewCityHandler(repo, nil, nil)
	rec := httptest.NewRecorder()
	h.Delete(rec, cityDeleteRequest("area-busy"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 OK", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "deleted") {
		t.Fatalf("body = %q, want deleted confirmation", rec.Body.String())
	}
}

func TestCityDelete_NotFoundReturns404(t *testing.T) {
	repo := &fakeAreaRepo{deleteFn: func(context.Context, string) error { return servicearea.ErrNotFound }}
	h := NewCityHandler(repo, nil, nil)
	rec := httptest.NewRecorder()
	h.Delete(rec, cityDeleteRequest("missing"))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

// A genuine database failure (not an FK/domain case) must yield a generic 500.
func TestCityDelete_DBErrorIsGeneric500(t *testing.T) {
	repo := &fakeAreaRepo{deleteFn: func(context.Context, string) error {
		return errors.New(`pq: FATAL: sorry, too many clients already`)
	}}
	h := NewCityHandler(repo, nil, nil)
	rec := httptest.NewRecorder()
	h.Delete(rec, cityDeleteRequest("area-1"))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "pq:") {
		t.Fatalf("body = %q, raw DB error leaked", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "internal error") {
		t.Fatalf("body = %q, want generic internal error", rec.Body.String())
	}
}
