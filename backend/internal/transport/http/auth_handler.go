package http

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"evik/backend/internal/auth"
)

type AuthHandler struct {
	tokens        *auth.TokenManager
	adminUserID   string
	adminPassword string
}

func NewAuthHandler(tokens *auth.TokenManager, adminUserID string, adminPassword string) *AuthHandler {
	return &AuthHandler{
		tokens:        tokens,
		adminUserID:   strings.TrimSpace(adminUserID),
		adminPassword: adminPassword,
	}
}

type loginRequest struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type adminLoginRequest struct {
	UserID   string `json:"user_id"`
	Password string `json:"password"`
}

type authTokensResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	role := auth.Role(req.Role)
	if req.UserID == "" || !auth.IsValidRole(role) {
		writeAuthError(w, http.StatusBadRequest, "user_id and valid role are required")
		return
	}
	if role == auth.RoleAdmin {
		writeAuthError(w, http.StatusForbidden, "admin login is not allowed on this endpoint")
		return
	}

	accessToken, refreshToken, err := h.tokens.Issue(req.UserID, role)
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"tokens": authTokensResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			TokenType:    "Bearer",
		},
		"user": map[string]any{
			"id":   req.UserID,
			"role": role,
		},
	})
}

func (h *AuthHandler) AdminLogin(w http.ResponseWriter, r *http.Request) {
	var req adminLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	userID := strings.TrimSpace(req.UserID)
	if userID == "" {
		userID = h.adminUserID
	}
	if h.adminUserID == "" || h.adminPassword == "" {
		writeAuthError(w, http.StatusServiceUnavailable, "admin auth is not configured")
		return
	}
	if subtle.ConstantTimeCompare([]byte(userID), []byte(h.adminUserID)) != 1 ||
		subtle.ConstantTimeCompare([]byte(req.Password), []byte(h.adminPassword)) != 1 {
		writeAuthError(w, http.StatusUnauthorized, "invalid admin credentials")
		return
	}

	accessToken, refreshToken, err := h.tokens.Issue(h.adminUserID, auth.RoleAdmin)
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"tokens": authTokensResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			TokenType:    "Bearer",
		},
		"user": map[string]any{
			"id":   h.adminUserID,
			"role": auth.RoleAdmin,
		},
	})
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.RefreshToken == "" {
		writeAuthError(w, http.StatusBadRequest, "refresh_token is required")
		return
	}

	claims, err := h.tokens.ParseRefreshToken(req.RefreshToken)
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	accessToken, refreshToken, err := h.tokens.Issue(claims.UserID, claims.Role)
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"tokens": authTokensResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			TokenType:    "Bearer",
		},
	})
}

func (h *AuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user": map[string]any{
			"id":   userID,
			"role": role,
		},
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func asAuthError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, ErrUnauthorized) {
		return err
	}
	return errors.New("unauthorized")
}
