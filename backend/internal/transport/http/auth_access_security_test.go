package http

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"evik/backend/internal/auth"
	userdomain "evik/backend/internal/domain/user"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// Security-layer tests for authentication (JWT) and role-based access control
// (RBAC). Two router shapes are used:
//
//  1. The REAL production router (NewRouter) with a real AuthHandler and a real
//     RateLimiter; all business handlers are zero-value stubs because the routes
//     under test are rejected by the auth/RBAC middleware BEFORE the handler is
//     reached (401/403), or served by the real AuthHandler (/auth/me, OTP).
//  2. A focused router wired from the REAL production middleware factories
//     (AuthMiddleware, RequireRoles, RateLimitByPhone) mirroring router.go's
//     role groups verbatim, with a probe terminal handler that returns a known
//     status. This is required for the positive admin cases (admin -> 2xx),
//     which would otherwise fall into DB-backed admin handlers.
//
// The probe only replaces the business handler; every status code decision in
// these tests is made by production middleware (JWT parse, role gate, rate
// limit), never by the probe.

const testJWTSecret = "test-secret-test-secret-test-secret"

func newRealRouter(tokens *auth.TokenManager, users userdomain.Repository, clock fixedHTTPClock) http.Handler {
	authHandler := NewAuthHandler(tokens, users, "admin", "admin-password", &seqID{}, clock, false, "", false, false)
	limiter := NewRateLimiter()
	return NewRouter(
		authHandler,
		&OrderHandler{}, &OfferHandler{}, &DriverHandler{}, &PaymentHandler{},
		&PricingHandler{}, &RoutingHandler{}, &AdminHandler{}, &SettingsHandler{},
		&ServiceAreaHandler{}, &CityHandler{}, &GeocodingHandler{}, &DriverLocationsHandler{},
		nil, tokens, nil, false, limiter, false,
	)
}

// newFocusedSecurityRouter mirrors the role groups in router.go using the real
// production middleware factories. probe returns wantStatus when reached.
func newFocusedSecurityRouter(tokens *auth.TokenManager, limiter *RateLimiter, probe func(w http.ResponseWriter, r *http.Request)) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	authMW := AuthMiddleware(tokens)

	r.Route("/api/v1", func(api chi.Router) {
		api.With(RateLimitByPhone(limiter, 3)).Post("/auth/otp/request", probe)
		api.With(RateLimitByPhone(limiter, 5)).Post("/auth/otp/verify", probe)

		api.Group(func(secured chi.Router) {
			secured.Use(authMW)
			// Any authenticated role.
			secured.Get("/auth/me", probe)
			// Client-only + admin (router.go line 73).
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/orders", probe)
			// Driver-only + admin (router.go line 81).
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/orders/{orderID}/accept", probe)
			// Driver-only + admin (router.go line 108).
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/driver/earnings", probe)
			// Client-only + admin (router.go line 102).
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Get("/payments/wallet", probe)

			// Admin-only subtree (router.go line 131-132).
			secured.Route("/admin", func(admin chi.Router) {
				admin.Use(RequireRoles(auth.RoleAdmin))
				admin.Get("/overview", probe)
				admin.Get("/orders", probe)
				admin.Get("/users", probe)
				admin.Get("/finance/refunds", probe)
				admin.Get("/finance/{reportType}", probe)
				admin.Get("/settings", probe)
			})
		})
	})
	return r
}

func probeOK(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"ok":true}`))
}

func newTokens(ttl time.Duration) *auth.TokenManager {
	return auth.NewTokenManager(testJWTSecret, ttl, time.Hour)
}

func seededUsers() *fakeUserRepository {
	repo := newFakeUserRepository()
	repo.users["client-1"] = &userdomain.User{ID: "client-1", Phone: "+79990000001", Name: "Client One", Role: auth.RoleClient, Status: userdomain.StatusActive}
	repo.users["driver-1"] = &userdomain.User{ID: "driver-1", Phone: "+79990000002", Name: "Driver One", Role: auth.RoleDriver, Status: userdomain.StatusActive}
	repo.users["admin-1"] = &userdomain.User{ID: "admin-1", Phone: "+79990000010", Name: "Admin One", Role: auth.RoleAdmin, Status: userdomain.StatusActive}
	return repo
}

func issueRoleToken(t *testing.T, tokens *auth.TokenManager, userID string, role auth.Role) string {
	t.Helper()
	access, _, err := tokens.Issue(userID, role)
	if err != nil {
		t.Fatalf("issue %s token: %v", role, err)
	}
	return access
}

func doRequest(r http.Handler, method, path, bearer string) *httptest.ResponseRecorder {
	var req *http.Request
	if method == http.MethodGet {
		req = httptest.NewRequest(method, path, nil)
	} else {
		req = httptest.NewRequest(method, path, nil)
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

// --- 1. JWT / access ---

func TestJWTAccess_ValidTokenSucceeds(t *testing.T) {
	tokens := newTokens(time.Minute)
	router := newRealRouter(tokens, seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})
	tok := issueRoleToken(t, tokens, "client-1", auth.RoleClient)

	rec := doRequest(router, http.MethodGet, "/api/v1/auth/me", tok)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &payload)
	if payload["user"].(map[string]any)["id"] != "client-1" {
		t.Fatalf("unexpected /auth/me payload: %s", rec.Body.String())
	}
}

func TestJWTAccess_ExpiredTokenRejected(t *testing.T) {
	tokens := newTokens(-time.Minute) // access token already expired at issuance
	router := newRealRouter(tokens, seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})
	tok := issueRoleToken(t, tokens, "client-1", auth.RoleClient)

	rec := doRequest(router, http.MethodGet, "/api/v1/auth/me", tok)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestJWTAccess_ForgedSignatureRejected(t *testing.T) {
	mint := auth.NewTokenManager("secret-forge", time.Minute, time.Hour)
	tok := issueRoleToken(t, mint, "client-1", auth.RoleClient)
	router := newRealRouter(newTokens(time.Minute), seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})

	rec := doRequest(router, http.MethodGet, "/api/v1/auth/me", tok)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestJWTAccess_MissingHeaderRejected(t *testing.T) {
	router := newRealRouter(newTokens(time.Minute), seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})

	rec := doRequest(router, http.MethodGet, "/api/v1/auth/me", "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestJWTAccess_GarbageBearerRejected(t *testing.T) {
	router := newRealRouter(newTokens(time.Minute), seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})
	for _, tc := range []struct {
		name, header string
	}{
		{"bare Bearer keyword", "Bearer"},
		{"short garbage token", "Bearer xxx"},
		{"three-part garbage", "Bearer aaa.bbb.ccc"},
		{"wrong scheme", "Basic abc123"},
		{"lowercase malformed", "bearer x"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/me", nil)
			req.Header.Set("Authorization", tc.header)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestJWTAccess_QueryParamTokenRejectedOnHTTP(t *testing.T) {
	// Regular HTTP must NOT accept ?access_token=: the token would leak into
	// access logs. Only the WebSocket route (WSAuthMiddleware) opts into
	// query-string tokens.
	tokens := newTokens(time.Minute)
	router := newRealRouter(tokens, seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})
	tok := issueRoleToken(t, tokens, "client-1", auth.RoleClient)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/me?access_token="+tok, nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401: query token must not authorize regular HTTP (body=%s)", rec.Code, rec.Body.String())
	}
}

// newWSFocusedRouter wires the production WSAuthMiddleware factory (exactly as
// router.go wires /ws/orders) to a probe terminal handler.
func newWSFocusedRouter(tokens *auth.TokenManager) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	r.With(WSAuthMiddleware(tokens)).Get("/ws/orders", probeOK)
	return r
}

func TestWSAuth_QueryTokenAccepted(t *testing.T) {
	tokens := newTokens(time.Minute)
	router := newWSFocusedRouter(tokens)
	tok := issueRoleToken(t, tokens, "driver-1", auth.RoleDriver)

	// Query-string token must keep authorizing the WS route.
	for _, qs := range []struct{ name, param string }{
		{"access_token", "/ws/orders?access_token=" + tok},
		{"token", "/ws/orders?token=" + tok},
	} {
		t.Run(qs.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, qs.param, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200: WS query token must authenticate (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestWSAuth_HeaderTokenAccepted(t *testing.T) {
	tokens := newTokens(time.Minute)
	router := newWSFocusedRouter(tokens)
	tok := issueRoleToken(t, tokens, "driver-1", auth.RoleDriver)

	req := httptest.NewRequest(http.MethodGet, "/ws/orders", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: WS header token must authenticate (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestWSAuth_MissingTokenRejected(t *testing.T) {
	tokens := newTokens(time.Minute)
	router := newWSFocusedRouter(tokens)

	req := httptest.NewRequest(http.MethodGet, "/ws/orders", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
}

// --- 2. RBAC matrix ---

func TestRBAC_AdminEndpointsForbiddenForNonAdmin(t *testing.T) {
	now := fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	router := newFocusedSecurityRouter(newTokens(time.Minute), NewRateLimiter(), probeOK)

	adminPaths := []string{
		"/api/v1/admin/overview",
		"/api/v1/admin/orders",
		"/api/v1/admin/users",
		"/api/v1/admin/finance/refunds",
		"/api/v1/admin/finance/payments",
		"/api/v1/admin/settings",
	}
	tokens := newTokens(time.Minute)
	clientTok := issueRoleToken(t, tokens, "client-1", auth.RoleClient)
	driverTok := issueRoleToken(t, tokens, "driver-1", auth.RoleDriver)

	// Cross-role on the real production router (admin subtree actually wired).
	realRouter := newRealRouter(tokens, seededUsers(), now)

	for _, path := range adminPaths {
		for _, tok := range []struct{ role, token string }{{"client", clientTok}, {"driver", driverTok}} {
			t.Run(tok.role+"->"+path, func(t *testing.T) {
				rec := doRequest(router, http.MethodGet, path, tok.token)
				if rec.Code != http.StatusForbidden {
					t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
				}
			})
			if path == "/api/v1/admin/overview" {
				rec := doRequest(realRouter, http.MethodGet, path, tok.token)
				if rec.Code != http.StatusForbidden {
					t.Fatalf("real router: status = %d, want 403", rec.Code)
				}
			}
		}
	}
}

func TestRBAC_AdminAccessGranted(t *testing.T) {
	router := newFocusedSecurityRouter(newTokens(time.Minute), NewRateLimiter(), probeOK)
	tokens := newTokens(time.Minute)
	adminTok := issueRoleToken(t, tokens, "admin-1", auth.RoleAdmin)

	adminPaths := []string{
		"/api/v1/admin/overview",
		"/api/v1/admin/orders",
		"/api/v1/admin/users",
		"/api/v1/admin/finance/refunds",
		"/api/v1/admin/finance/payments",
		"/api/v1/admin/settings",
	}
	for _, path := range adminPaths {
		t.Run(path, func(t *testing.T) {
			rec := doRequest(router, http.MethodGet, path, adminTok)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestRBAC_WrongRoleOnOwnerEndpointForbidden(t *testing.T) {
	router := newFocusedSecurityRouter(newTokens(time.Minute), NewRateLimiter(), probeOK)
	tokens := newTokens(time.Minute)
	clientTok := issueRoleToken(t, tokens, "client-1", auth.RoleClient)
	driverTok := issueRoleToken(t, tokens, "driver-1", auth.RoleDriver)

	cases := []struct {
		name, method, path, token string
	}{
		{"client on driver accept", http.MethodPost, "/api/v1/orders/order-1/accept", clientTok},
		{"client on driver earnings", http.MethodGet, "/api/v1/driver/earnings", clientTok},
		{"driver on client create order", http.MethodPost, "/api/v1/orders", driverTok},
		{"driver on client wallet", http.MethodGet, "/api/v1/payments/wallet", driverTok},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := doRequest(router, tc.method, tc.path, tc.token)
			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestRBAC_AdminBypassesRoleChecks(t *testing.T) {
	router := newFocusedSecurityRouter(newTokens(time.Minute), NewRateLimiter(), probeOK)
	tokens := newTokens(time.Minute)
	adminTok := issueRoleToken(t, tokens, "admin-1", auth.RoleAdmin)

	for _, tc := range []struct {
		name, method, path string
	}{
		{"admin on client create order", http.MethodPost, "/api/v1/orders"},
		{"admin on driver accept", http.MethodPost, "/api/v1/orders/order-1/accept"},
		{"admin on driver earnings", http.MethodGet, "/api/v1/driver/earnings"},
		{"admin on client wallet", http.MethodGet, "/api/v1/payments/wallet"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rec := doRequest(router, tc.method, tc.path, adminTok)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestRBAC_NoTokenOnAdminRejected(t *testing.T) {
	router := newRealRouter(newTokens(time.Minute), seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})

	rec := doRequest(router, http.MethodGet, "/api/v1/admin/overview", "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestRBAC_AnyAuthenticatedReachesMe(t *testing.T) {
	now := fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	tokens := newTokens(time.Minute)
	router := newRealRouter(tokens, seededUsers(), now)

	for _, tc := range []struct {
		role auth.Role
	}{
		{auth.RoleClient}, {auth.RoleDriver}, {auth.RoleAdmin},
	} {
		t.Run(string(tc.role), func(t *testing.T) {
			id := string(tc.role) + "-1"
			tok := issueRoleToken(t, tokens, id, tc.role)
			rec := doRequest(router, http.MethodGet, "/api/v1/auth/me", tok)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestRBAC_NoEscalation_RegisterAsAdminRejected(t *testing.T) {
	router := newRealRouter(newTokens(time.Minute), seededUsers(), fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)})

	rec := doRequestJSON(router, http.MethodPost, "/api/v1/auth/register", `{"phone":"+79990000009","full_name":"Wanna Be Admin","role":"admin","password":"password1"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (no escalation path via public register; body=%s)", rec.Code, rec.Body.String())
	}
}

func doRequestJSON(r http.Handler, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}
