package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
)

// Simple storage without external dependencies
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

func main() {
	http.HandleFunc("/healthz", healthHandler)
	http.HandleFunc("/api/v1/auth/send-sms", corsWrapper(sendSMSHandler))
	http.HandleFunc("/api/v1/auth/verify-sms", corsWrapper(verifySMSHandler))

	fmt.Println("🚀 Simple Auth Server starting on :8080")
	fmt.Println("📱 Test phone: +79123456789")
	fmt.Println("🔢 Test code: 1234")
	fmt.Println("✅ Ready for testing!")

	log.Fatal(http.ListenAndServe(":8080", nil))
}

func corsWrapper(handler func(http.ResponseWriter, *http.Request)) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		// CORS headers
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Credentials", "true")

		// Handle preflight
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		handler(w, r)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func sendSMSHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "Only POST allowed")
		return
	}

	var req SendSMSRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON")
		return
	}

	if req.Phone == "" {
		writeError(w, http.StatusBadRequest, "missing_phone", "Phone number is required")
		return
	}

	// Generate simple verification ID
	verificationID := generateID()
	expiresAt := time.Now().Add(5 * time.Minute)

	// Store in memory
	codesMutex.Lock()
	verificationCodes[verificationID] = VerificationData{
		Phone:     req.Phone,
		Code:      "1234", // Always 1234 for testing
		ExpiresAt: expiresAt,
	}
	codesMutex.Unlock()

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
	if r.Method != "POST" {
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "Only POST allowed")
		return
	}

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

	// Generate simple JWT token
	userID := fmt.Sprintf("user_%s", req.Phone[2:]) // Remove +7 prefix
	expiresAt := time.Now().Add(1 * time.Hour)

	accessToken := generateSimpleJWT(userID, req.Phone, "client", expiresAt)

	// Create user response
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

func generateID() string {
	// Simple ID generation without external deps
	return fmt.Sprintf("verify_%d", time.Now().UnixNano())
}

func generateSimpleJWT(userID, phone, role string, expiresAt time.Time) string {
	// Simple JWT without external library (just for testing)
	header := `{"alg":"HS256","typ":"JWT"}`
	payload := fmt.Sprintf(`{"sub":"%s","phone":"%s","role":"%s","exp":%d,"iat":%d,"iss":"evik-test"}`,
		userID, phone, role, expiresAt.Unix(), time.Now().Unix())

	// Base64 encode
	headerB64 := base64.RawURLEncoding.EncodeToString([]byte(header))
	payloadB64 := base64.RawURLEncoding.EncodeToString([]byte(payload))

	// Create signature
	secret := "evik-test-secret"
	signData := headerB64 + "." + payloadB64
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(signData))
	signature := base64.RawURLEncoding.EncodeToString(h.Sum(nil))

	return signData + "." + signature
}