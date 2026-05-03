package http

import (
	"encoding/json"
	"net/http"
	"regexp"

	"evik/backend/internal/domain/auth"
)

type AuthSMSHandler struct {
	smsService *auth.SMSService
	jwtService *auth.JWTService
}

type SendSMSRequest struct {
	Phone string `json:"phone"`
}

type SendSMSResponse struct {
	VerificationID string `json:"verification_id"`
	ExpiresAt      string `json:"expires_at"`
}

type VerifySMSRequest struct {
	VerificationID string `json:"verification_id"`
	Code           string `json:"code"`
	Phone          string `json:"phone"`
}

type VerifySMSResponse struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	ExpiresAt    string      `json:"expires_at"`
	User         interface{} `json:"user"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func NewAuthSMSHandler(smsService *auth.SMSService, jwtService *auth.JWTService) *AuthSMSHandler {
	return &AuthSMSHandler{
		smsService: smsService,
		jwtService: jwtService,
	}
}

func (h *AuthSMSHandler) SendSMS(w http.ResponseWriter, r *http.Request) {
	var req SendSMSRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON")
		return
	}

	// Validate phone number
	if !h.isValidPhone(req.Phone) {
		h.writeError(w, http.StatusBadRequest, "invalid_phone", "Invalid phone number format")
		return
	}

	// Send verification code
	result, err := h.smsService.SendVerificationCode(r.Context(), req.Phone)
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, "sms_send_failed", "Failed to send SMS")
		return
	}

	response := SendSMSResponse{
		VerificationID: result.VerificationID,
		ExpiresAt:      result.ExpiresAt.Format("2006-01-02T15:04:05Z07:00"),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func (h *AuthSMSHandler) VerifySMS(w http.ResponseWriter, r *http.Request) {
	var req VerifySMSRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON")
		return
	}

	// Validate inputs
	if req.VerificationID == "" || req.Code == "" || req.Phone == "" {
		h.writeError(w, http.StatusBadRequest, "missing_fields", "Missing required fields")
		return
	}

	if !h.isValidPhone(req.Phone) {
		h.writeError(w, http.StatusBadRequest, "invalid_phone", "Invalid phone number format")
		return
	}

	// Verify code
	isValid, err := h.smsService.VerifyCode(r.Context(), req.VerificationID, req.Code)
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, "verification_failed", "Failed to verify code")
		return
	}

	if !isValid {
		h.writeError(w, http.StatusBadRequest, "invalid_code", "Invalid or expired verification code")
		return
	}

	// TODO: Check if user exists, create if not exists
	// For now, creating a mock user ID
	userID := "user_" + req.Phone[2:] // Remove +7 prefix
	role := "client"

	// Generate JWT tokens
	tokenPair, err := h.jwtService.GenerateTokenPair(r.Context(), userID, role, req.Phone)
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, "token_generation_failed", "Failed to generate tokens")
		return
	}

	// TODO: Return actual user data from database
	user := map[string]interface{}{
		"id":    userID,
		"phone": req.Phone,
		"role":  role,
	}

	response := VerifySMSResponse{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresAt:    tokenPair.ExpiresAt.Format("2006-01-02T15:04:05Z07:00"),
		User:         user,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func (h *AuthSMSHandler) RefreshToken(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON")
		return
	}

	if req.RefreshToken == "" {
		h.writeError(w, http.StatusBadRequest, "missing_refresh_token", "Refresh token is required")
		return
	}

	// Refresh tokens
	tokenPair, err := h.jwtService.RefreshTokens(r.Context(), req.RefreshToken)
	if err != nil {
		h.writeError(w, http.StatusUnauthorized, "invalid_refresh_token", "Invalid or expired refresh token")
		return
	}

	response := map[string]interface{}{
		"access_token":  tokenPair.AccessToken,
		"refresh_token": tokenPair.RefreshToken,
		"expires_at":    tokenPair.ExpiresAt.Format("2006-01-02T15:04:05Z07:00"),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func (h *AuthSMSHandler) isValidPhone(phone string) bool {
	// Russian phone number format: +7XXXXXXXXXX
	phoneRegex := regexp.MustCompile(`^\+7\d{10}$`)
	return phoneRegex.MatchString(phone)
}

func (h *AuthSMSHandler) writeError(w http.ResponseWriter, statusCode int, errorCode, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(ErrorResponse{
		Error:   errorCode,
		Message: message,
	})
}