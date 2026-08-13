package http

import (
	"context"
	"net/http"
	"strings"

	"evik/backend/internal/auth"
)

// UserStatusChecker reports whether the account behind an access token is
// still usable. When wired into the middleware, deleted/blocked accounts are
// rejected immediately even while their (already issued) JWT is valid.
type UserStatusChecker interface {
	IsUserActive(ctx context.Context, userID string) (bool, error)
}

func AuthMiddleware(tokens *auth.TokenManager, checkers ...UserStatusChecker) func(http.Handler) http.Handler {
	return authMiddleware(tokens, false, checkers...)
}

// WSAuthMiddleware authenticates a WebSocket handshake. Browsers cannot set
// custom headers on a WS handshake, so the access token is also accepted from
// the query string (?access_token= / ?token=). Apply it ONLY to the /ws route;
// regular HTTP must use AuthMiddleware so a JWT never leaks into logs via the
// query string.
func WSAuthMiddleware(tokens *auth.TokenManager, checkers ...UserStatusChecker) func(http.Handler) http.Handler {
	return authMiddleware(tokens, true, checkers...)
}

func authMiddleware(tokens *auth.TokenManager, allowQueryToken bool, checkers ...UserStatusChecker) func(http.Handler) http.Handler {
	var checker UserStatusChecker
	if len(checkers) > 0 {
		checker = checkers[0]
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rawToken := extractAccessToken(r)
			if rawToken == "" && allowQueryToken {
				rawToken = strings.TrimSpace(r.URL.Query().Get("access_token"))
				if rawToken == "" {
					rawToken = strings.TrimSpace(r.URL.Query().Get("token"))
				}
			}
			if rawToken == "" {
				writeAuthError(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			claims, err := tokens.ParseAccessToken(rawToken)
			if err != nil {
				writeAuthError(w, http.StatusUnauthorized, "invalid access token")
				return
			}
			if checker != nil {
				active, err := checker.IsUserActive(r.Context(), claims.UserID)
				if err != nil {
					writeAuthError(w, http.StatusInternalServerError, "internal server error")
					return
				}
				if !active {
					writeAuthError(w, http.StatusUnauthorized, "account is deleted or blocked")
					return
				}
			}

			next.ServeHTTP(w, r.WithContext(withAuth(r.Context(), claims.UserID, claims.Role)))
		})
	}
}

// extractAccessToken reads the access token from the Authorization header only.
// Query-string tokens are deliberately NOT accepted on regular HTTP routes so
// a JWT cannot leak into access logs; the WebSocket route uses
// WSAuthMiddleware, which opts into query tokens explicitly.
func extractAccessToken(r *http.Request) string {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return strings.TrimSpace(header[len("Bearer "):])
	}
	return ""
}

func RequireRoles(allowed ...auth.Role) func(http.Handler) http.Handler {
	set := make(map[auth.Role]struct{}, len(allowed))
	for _, role := range allowed {
		set[role] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			role, err := roleFromContext(r.Context())
			if err != nil {
				writeAuthError(w, http.StatusUnauthorized, "unauthorized")
				return
			}
			if _, ok := set[role]; !ok {
				writeAuthError(w, http.StatusForbidden, "forbidden")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func writeAuthError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(`{"error":"` + message + `"}`))
}
