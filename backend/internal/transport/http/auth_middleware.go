package http

import (
	"net/http"
	"strings"

	"evik/backend/internal/auth"
)

func AuthMiddleware(tokens *auth.TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rawToken := extractAccessToken(r)
			if rawToken == "" {
				writeAuthError(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			claims, err := tokens.ParseAccessToken(rawToken)
			if err != nil {
				writeAuthError(w, http.StatusUnauthorized, "invalid access token")
				return
			}

			next.ServeHTTP(w, r.WithContext(withAuth(r.Context(), claims.UserID, claims.Role)))
		})
	}
}

func extractAccessToken(r *http.Request) string {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return strings.TrimSpace(header[len("Bearer "):])
	}
	return strings.TrimSpace(r.URL.Query().Get("access_token"))
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
