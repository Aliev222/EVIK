package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// In-memory storage
var (
	verificationCodes = make(map[string]VerificationData)
	codesMutex       = sync.RWMutex{}
)

type VerificationData struct {
	Phone     string
	Code      string
	ExpiresAt time.Time
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

const jwtSecret = "evik-test-secret-key"

func main() {
	r := chi.NewRouter()

	// Middleware
	r.Use(middleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"}, // Allow all for testing
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Health endpoint
	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Auth routes
	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/send-sms", sendSMSHandler)
		api.Post("/auth/verify-sms", verifySMSHandler)
	})

	fmt.Println("🚀 Test auth server starting on :8080")
	fmt.Println("📱 Test phone: +79123456789")
	fmt.Println("🔢 Test code: 1234")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func sendSMSHandler(w http.ResponseWriter, r *http.Request) {
	var req SendSMSRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON")
		return
	}

	if req.Phone == "" {
		writeError(w, http.StatusBadRequest, "missing_phone", "Phone number is required")
		return
	}

	// Generate verification ID
	verificationID := uuid.New().String()
	expiresAt := time.Now().Add(5 * time.Minute)

	// Store verification data in memory
	codesMutex.Lock()
	verificationCodes[verificationID] = VerificationData{
		Phone:     req.Phone,
		Code:      "1234", // Always 1234 for testing
		ExpiresAt: expiresAt,
	}
	codesMutex.Unlock()

	// Log for testing
	fmt.Printf("📱 SMS sent to %s, verification_id: %s, code: 1234\n", req.Phone, verificationID)

	response := SendSMSResponse{
		VerificationID: verificationID,
		ExpiresAt:      expiresAt.Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func verifySMSHandler(w http.ResponseWriter, r *http.Request) {
	var req VerifySMSRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON")
		return
	}

	if req.VerificationID == "" || req.Code == "" || req.Phone == "" {
		writeError(w, http.StatusBadRequest, "missing_fields", "Missing required fields")
		return
	}

	// Get verification data
	codesMutex.RLock()
	verifyData, exists := verificationCodes[req.VerificationID]
	codesMutex.RUnlock()

	if !exists {
		writeError(w, http.StatusBadRequest, "invalid_verification_id", "Invalid or expired verification ID")
		return
	}

	// Check expiration
	if time.Now().After(verifyData.ExpiresAt) {
		codesMutex.Lock()
		delete(verificationCodes, req.VerificationID)
		codesMutex.Unlock()
		writeError(w, http.StatusBadRequest, "expired_code", "Verification code expired")
		return
	}

	// Check code
	if verifyData.Code != req.Code {
		writeError(w, http.StatusBadRequest, "invalid_code", "Invalid verification code")
		return
	}

	// Check phone match
	if verifyData.Phone != req.Phone {
		writeError(w, http.StatusBadRequest, "phone_mismatch", "Phone number mismatch")
		return
	}

	// Delete used verification code
	codesMutex.Lock()
	delete(verificationCodes, req.VerificationID)
	codesMutex.Unlock()

	// Generate JWT token (simplified)
	userID := fmt.Sprintf("user_%s", req.Phone[2:]) // Remove +7 prefix
	expiresAt := time.Now().Add(1 * time.Hour)

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":   userID,
		"phone": req.Phone,
		"role":  "client",
		"exp":   expiresAt.Unix(),
		"iat":   time.Now().Unix(),
		"iss":   "evik-test",
	})

	accessToken, err := token.SignedString([]byte(jwtSecret))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token_error", "Failed to generate token")
		return
	}

	// Create mock user
	user := map[string]interface{}{
		"id":    userID,
		"phone": req.Phone,
		"role":  "client",
	}

	response := VerifySMSResponse{
		AccessToken:  accessToken,
		RefreshToken: accessToken, // Same for testing
		ExpiresAt:    expiresAt.Format(time.RFC3339),
		User:         user,
	}

	fmt.Printf("✅ User authenticated: %s (ID: %s)\n", req.Phone, userID)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func writeError(w http.ResponseWriter, statusCode int, errorCode, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(ErrorResponse{
		Error:   errorCode,
		Message: message,
	})
}