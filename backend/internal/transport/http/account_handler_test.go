package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"evik/backend/internal/auth"
	acc "evik/backend/internal/usecase/account"
)

type fakeDeleteRepo struct {
	err error
}

func (f *fakeDeleteRepo) Delete(_ context.Context, _ string, _ auth.Role, _ time.Time) error {
	return f.err
}

func newAccountTestRouter(repo acc.AccountRepository) http.Handler {
	uc := acc.NewUseCase(repo)
	h := NewAccountHandler(uc)
	r := http.NewServeMux()
	r.HandleFunc("/account", h.Delete)
	return r
}

func doAccountDelete(t *testing.T, userID string, role auth.Role, repo acc.AccountRepository, checker UserStatusChecker) *httptest.ResponseRecorder {
	t.Helper()
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	access, _, err := tokens.Issue(userID, role)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	mw := AuthMiddleware(tokens, checker)
	router := newAccountTestRouter(repo)

	req := httptest.NewRequest(http.MethodDelete, "/account", nil)
	req.Header.Set("Authorization", "Bearer "+access)

	rec := httptest.NewRecorder()
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		router.ServeHTTP(w, r)
	})).ServeHTTP(rec, req)
	return rec
}

type activeRepo struct {
	active bool
}

func (a *activeRepo) IsUserActive(_ context.Context, _ string) (bool, error) {
	return a.active, nil
}

func TestAccountDeleteSuccess(t *testing.T) {
	rec := doAccountDelete(t, "client-1", auth.RoleClient, &fakeDeleteRepo{}, &activeRepo{active: true})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %s)", rec.Code, rec.Body.String())
	}
}

func TestAccountDeleteActiveOrderConflict(t *testing.T) {
	rec := doAccountDelete(t, "client-1", auth.RoleClient, &fakeDeleteRepo{err: acc.ErrActiveOrder}, &activeRepo{active: true})
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409 (body: %s)", rec.Code, rec.Body.String())
	}
}

func TestAccountDeleteOutstandingBalanceConflict(t *testing.T) {
	rec := doAccountDelete(t, "driver-1", auth.RoleDriver, &fakeDeleteRepo{err: acc.ErrOutstandingDriverBalance}, &activeRepo{active: true})
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409 (body: %s)", rec.Code, rec.Body.String())
	}
}

func TestAccountDeleteBlockedWhenUserInactive(t *testing.T) {
	// A deleted user's still-valid JWT must not reach the delete endpoint.
	rec := doAccountDelete(t, "client-1", auth.RoleClient, &fakeDeleteRepo{}, &activeRepo{active: false})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body: %s)", rec.Code, rec.Body.String())
	}
}