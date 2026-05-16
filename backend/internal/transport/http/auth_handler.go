package http

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"evik/backend/internal/auth"
	userdomain "evik/backend/internal/domain/user"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	tokens         *auth.TokenManager
	users          userdomain.Repository
	adminUserID    string
	adminPassword  string
	idGen          interface{ NewID() string }
	clock          interface{ Now() time.Time }
	exposeOTPCodes bool
	fixedOTPCode   string
}

func NewAuthHandler(tokens *auth.TokenManager, users userdomain.Repository, adminUserID string, adminPassword string, idGen interface{ NewID() string }, clock interface{ Now() time.Time }, exposeOTPCodes bool, fixedOTPCode string) *AuthHandler {
	return &AuthHandler{
		tokens:         tokens,
		users:          users,
		adminUserID:    strings.TrimSpace(adminUserID),
		adminPassword:  adminPassword,
		idGen:          idGen,
		clock:          clock,
		exposeOTPCodes: exposeOTPCodes,
		fixedOTPCode:   strings.TrimSpace(fixedOTPCode),
	}
}

type loginRequest struct {
	Phone    string `json:"phone"`
	Password string `json:"password"`
	Role     string `json:"role"`
}

type registerRequest struct {
	Phone    string `json:"phone"`
	Password string `json:"password"`
	FullName string `json:"full_name"`
	Role     string `json:"role"`
}

type otpRequest struct {
	Phone string `json:"phone"`
	Role  string `json:"role"`
}

type otpVerifyRequest struct {
	Phone    string `json:"phone"`
	Code     string `json:"code"`
	Role     string `json:"role"`
	FullName string `json:"full_name"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type adminLoginRequest struct {
	UserID   string `json:"user_id"`
	Password string `json:"password"`
}

type deviceTokenRequest struct {
	FCMToken   string `json:"fcm_token"`
	Role       string `json:"role"`
	Platform   string `json:"platform"`
	AppVersion string `json:"app_version"`
}

type authTokensResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
}

// Login authenticates a client or driver by phone + password and returns
// an access/refresh token pair plus the user summary.
//
// @Summary      Login by phone + password
// @Description  Authenticates a non-admin user (client or driver) and issues JWT tokens. Admin must use /auth/admin/login.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body  body      LoginRequest  true  "Login payload"
// @Success      200   {object}  LoginResponse
// @Failure      400   {object}  ErrorResponse  "missing or malformed fields"
// @Failure      401   {object}  ErrorResponse  "invalid credentials"
// @Failure      403   {object}  ErrorResponse  "admin login is not allowed on this endpoint"
// @Router       /auth/login [post]
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	role := auth.Role(req.Role)
	phone := normalizePhone(req.Phone)
	if phone == "" || req.Password == "" || !auth.IsValidRole(role) {
		writeAuthError(w, http.StatusBadRequest, "phone, password and valid role are required")
		return
	}
	if role == auth.RoleAdmin {
		writeAuthError(w, http.StatusForbidden, "admin login is not allowed on this endpoint")
		return
	}
	user, err := h.users.GetByPhoneAndRole(r.Context(), phone, string(role))
	if err != nil || user.PasswordHash == nil || user.Status != userdomain.StatusActive {
		writeAuthError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(*user.PasswordHash), []byte(req.Password)) != nil {
		writeAuthError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	accessToken, refreshToken, err := h.issueTokens(r.Context(), user.ID, role)
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
			"id":        user.ID,
			"role":      role,
			"phone":     user.Phone,
			"full_name": user.Name,
		},
	})
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	role := auth.Role(req.Role)
	phone := normalizePhone(req.Phone)
	name := strings.TrimSpace(req.FullName)
	if phone == "" || len(req.Password) < 8 || name == "" || (role != auth.RoleClient && role != auth.RoleDriver) {
		writeAuthError(w, http.StatusBadRequest, "phone, full_name, role and password(>=8) are required")
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to hash password")
		return
	}
	now := h.clock.Now()
	passwordHash := string(hash)
	user := &userdomain.User{
		ID:           h.idGen.NewID(),
		Phone:        phone,
		Name:         name,
		Role:         role,
		PasswordHash: &passwordHash,
		Status:       userdomain.StatusActive,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if err := h.users.Create(r.Context(), user); err != nil {
		if errors.Is(err, userdomain.ErrUserAlreadyExists) {
			writeAuthError(w, http.StatusConflict, "user already exists")
			return
		}
		writeAuthError(w, http.StatusInternalServerError, "failed to create user")
		return
	}
	accessToken, refreshToken, err := h.issueTokens(r.Context(), user.ID, role)
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"tokens": authTokensResponse{AccessToken: accessToken, RefreshToken: refreshToken, TokenType: "Bearer"},
		"user":   map[string]any{"id": user.ID, "role": role, "phone": user.Phone, "full_name": user.Name},
	})
}

func (h *AuthHandler) RequestOTP(w http.ResponseWriter, r *http.Request) {
	var req otpRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	role := auth.Role(req.Role)
	phone := normalizePhone(req.Phone)
	if phone == "" || (role != auth.RoleClient && role != auth.RoleDriver) {
		writeAuthError(w, http.StatusBadRequest, "phone and valid role are required")
		return
	}
	code := h.fixedOTPCode
	if code == "" {
		var err error
		code, err = randomOTP()
		if err != nil {
			writeAuthError(w, http.StatusInternalServerError, "failed to create otp")
			return
		}
	}
	now := h.clock.Now()
	otp := &userdomain.PhoneOTP{
		ID:        h.idGen.NewID(),
		Phone:     phone,
		Role:      role,
		CodeHash:  otpHash(phone, role, code),
		ExpiresAt: now.Add(10 * time.Minute),
		CreatedAt: now,
	}
	if err := h.users.CreatePhoneOTP(r.Context(), otp); err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to create otp")
		return
	}
	payload := map[string]any{"otp_required": true, "expires_in_seconds": 600}
	if h.exposeOTPCodes {
		payload["debug_otp"] = code
	}
	writeJSON(w, http.StatusAccepted, payload)
}

func (h *AuthHandler) VerifyOTP(w http.ResponseWriter, r *http.Request) {
	var req otpVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	role := auth.Role(req.Role)
	phone := normalizePhone(req.Phone)
	code := onlyDigitsAuth(req.Code)
	if phone == "" || len(code) != 6 || (role != auth.RoleClient && role != auth.RoleDriver) {
		writeAuthError(w, http.StatusBadRequest, "phone, 6-digit code and valid role are required")
		return
	}
	if _, err := h.users.ConsumePhoneOTP(r.Context(), phone, string(role), otpHash(phone, role, code), h.clock.Now()); err != nil {
		writeAuthError(w, http.StatusUnauthorized, "invalid or expired otp")
		return
	}
	user, err := h.users.GetByPhoneAndRole(r.Context(), phone, string(role))
	if errors.Is(err, userdomain.ErrUserNotFound) {
		now := h.clock.Now()
		name := strings.TrimSpace(req.FullName)
		if name == "" {
			name = phone
		}
		user = &userdomain.User{
			ID:        h.idGen.NewID(),
			Phone:     phone,
			Name:      name,
			Role:      role,
			Status:    userdomain.StatusActive,
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := h.users.Create(r.Context(), user); err != nil {
			writeAuthError(w, http.StatusInternalServerError, "failed to create user")
			return
		}
	} else if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to load user")
		return
	}
	if user.Status != userdomain.StatusActive {
		writeAuthError(w, http.StatusForbidden, "user is blocked")
		return
	}
	accessToken, refreshToken, err := h.issueTokens(r.Context(), user.ID, role)
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"tokens": authTokensResponse{AccessToken: accessToken, RefreshToken: refreshToken, TokenType: "Bearer"},
		"user":   map[string]any{"id": user.ID, "role": role, "phone": user.Phone, "full_name": user.Name},
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

	accessToken, refreshToken, err := h.issueTokens(r.Context(), h.adminUserID, auth.RoleAdmin)
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
	session, err := h.users.GetActiveRefreshSessionByHash(r.Context(), tokenHash(req.RefreshToken))
	if err != nil || session.UserID != claims.UserID || session.Role != claims.Role {
		writeAuthError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	if err := h.users.RevokeRefreshSession(r.Context(), session.ID, h.clock.Now()); err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to rotate refresh token")
		return
	}
	accessToken, refreshToken, err := h.issueTokens(r.Context(), claims.UserID, claims.Role)
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

func (h *AuthHandler) issueTokens(ctx context.Context, userID string, role auth.Role) (string, string, error) {
	accessToken, refreshToken, err := h.tokens.Issue(userID, role)
	if err != nil {
		return "", "", err
	}
	session := &userdomain.RefreshSession{
		ID:        h.idGen.NewID(),
		UserID:    userID,
		Role:      role,
		TokenHash: tokenHash(refreshToken),
		ExpiresAt: h.clock.Now().Add(7 * 24 * time.Hour),
		CreatedAt: h.clock.Now(),
	}
	if err := h.users.CreateRefreshSession(ctx, session); err != nil {
		return "", "", err
	}
	return accessToken, refreshToken, nil
}

func normalizePhone(input string) string {
	digits := onlyDigitsAuth(input)
	if digits == "" {
		return ""
	}
	if len(digits) == 11 && (strings.HasPrefix(digits, "7") || strings.HasPrefix(digits, "8")) {
		return "+7" + digits[1:]
	}
	if len(digits) == 10 {
		return "+7" + digits
	}
	if strings.HasPrefix(strings.TrimSpace(input), "+") && len(digits) >= 10 {
		return "+" + digits
	}
	return ""
}

func onlyDigitsAuth(value string) string {
	var b strings.Builder
	for _, r := range value {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func randomOTP() (string, error) {
	var buf [3]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", err
	}
	n := int(buf[0])<<16 | int(buf[1])<<8 | int(buf[2])
	return fmt.Sprintf("%06d", n%1000000), nil
}

func otpHash(phone string, role auth.Role, code string) string {
	sum := sha256.Sum256([]byte(phone + ":" + string(role) + ":" + code))
	return hex.EncodeToString(sum[:])
}

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
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

func (h *AuthHandler) UpsertDeviceToken(w http.ResponseWriter, r *http.Request) {
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

	var req deviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if strings.TrimSpace(req.FCMToken) == "" {
		writeAuthError(w, http.StatusBadRequest, "fcm_token is required")
		return
	}
	if req.Role != "" && auth.Role(req.Role) != role {
		writeAuthError(w, http.StatusForbidden, "role does not match access token")
		return
	}

	now := h.clock.Now()
	token := &userdomain.DeviceToken{
		UserID:     userID,
		Role:       role,
		FCMToken:   strings.TrimSpace(req.FCMToken),
		Platform:   sanitizeDeviceField(req.Platform, 32),
		AppVersion: sanitizeDeviceField(req.AppVersion, 64),
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	if err := h.users.UpsertDeviceToken(r.Context(), token); err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to save device token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (h *AuthHandler) RevokeDeviceToken(w http.ResponseWriter, r *http.Request) {
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

	var req deviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if strings.TrimSpace(req.FCMToken) == "" {
		writeAuthError(w, http.StatusBadRequest, "fcm_token is required")
		return
	}
	if err := h.users.RevokeDeviceToken(r.Context(), userID, string(role), strings.TrimSpace(req.FCMToken), h.clock.Now()); err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to revoke device token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func sanitizeDeviceField(value string, maxLen int) string {
	clean := strings.TrimSpace(value)
	if len(clean) > maxLen {
		return clean[:maxLen]
	}
	return clean
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
