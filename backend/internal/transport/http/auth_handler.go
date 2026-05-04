package http

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"

	"evik/backend/internal/auth"
)

type AuthHandler struct {
	tokens *auth.TokenManager
}

func NewAuthHandler(tokens *auth.TokenManager) *AuthHandler {
	return &AuthHandler{tokens: tokens}
}

type loginRequest struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
}

type registerRequest struct {
	Phone    string `json:"phone"`     // Номер телефона как логин
	Name     string `json:"name"`      // Имя пользователя
	Password string `json:"password"`  // Пароль
	Role     string `json:"role"`      // "client" или "driver"
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
	accessToken, refreshToken, err := h.tokens.Issue(claims.UserID, auth.Role(claims.Role))
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

// AdminLogin - вход для администратора с паролем
func (h *AuthHandler) AdminLogin(w http.ResponseWriter, r *http.Request) {
	var req adminLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Проверяем админский пароль из переменной окружения
	expectedPassword := getEnv("ADMIN_PASSWORD", "admin123") // fallback пароль для разработки

	if req.Password != expectedPassword {
		writeAuthError(w, http.StatusUnauthorized, "invalid admin password")
		return
	}

	// Устанавливаем admin роль если пароль верный
	adminUserID := req.UserID
	if adminUserID == "" {
		adminUserID = "admin"
	}

	accessToken, refreshToken, err := h.tokens.IssueTokens(adminUserID, auth.RoleAdmin)
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
			"id":   adminUserID,
			"role": "admin",
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

func getEnv(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

// Register - простая регистрация по номеру телефона + пароль (без SMS)
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAuthError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Валидация
	if req.Phone == "" || req.Password == "" || req.Name == "" {
		writeAuthError(w, http.StatusBadRequest, "phone, name and password are required")
		return
	}

	// Валидация роли
	if req.Role != "client" && req.Role != "driver" {
		writeAuthError(w, http.StatusBadRequest, "role must be 'client' or 'driver'")
		return
	}

	// Нормализация номера телефона (убираем пробелы, добавляем +7 если нужно)
	phone := strings.TrimSpace(req.Phone)
	if !strings.HasPrefix(phone, "+") {
		if strings.HasPrefix(phone, "8") {
			phone = "+7" + phone[1:]
		} else if strings.HasPrefix(phone, "7") {
			phone = "+" + phone
		} else {
			phone = "+7" + phone
		}
	}

	// Генерируем userID из номера телефона (убираем + и пробелы)
	userID := strings.ReplaceAll(phone, "+", "")
	userID = strings.ReplaceAll(userID, " ", "")
	userID = strings.ReplaceAll(userID, "-", "")

	// TODO: В реальном приложении здесь был бы:
	// 1. Хеширование пароля (bcrypt)
	// 2. Сохранение в базу данных
	// 3. Проверка что пользователь не существует
	// Пока что просто генерируем токены

	// Генерируем JWT токены
	accessToken, refreshToken, err := h.tokens.IssueTokens(userID, auth.Role(req.Role))
	if err != nil {
		writeAuthError(w, http.StatusInternalServerError, "failed to create account")
		return
	}

	// Возвращаем успешный ответ
	writeJSON(w, http.StatusCreated, map[string]any{
		"tokens": authTokensResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			TokenType:    "Bearer",
		},
		"user": map[string]any{
			"id":    userID,
			"phone": phone,
			"name":  req.Name,
			"role":  req.Role,
		},
		"message": "Registration successful",
	})
}
