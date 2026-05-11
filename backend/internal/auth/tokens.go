package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type Role string

const (
	RoleClient Role = "client"
	RoleDriver Role = "driver"
	RoleAdmin  Role = "admin"
)

var (
	ErrInvalidToken = errors.New("invalid token")
	ErrInvalidRole  = errors.New("invalid role")
)

type Claims struct {
	UserID string `json:"uid"`
	Role   Role   `json:"role"`
	Type   string `json:"typ"`
	jwt.RegisteredClaims
}

func IsValidRole(role Role) bool {
	switch role {
	case RoleClient, RoleDriver, RoleAdmin:
		return true
	default:
		return false
	}
}

type TokenManager struct {
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
	now        func() time.Time
}

func NewTokenManager(secret string, accessTTL, refreshTTL time.Duration) *TokenManager {
	return &TokenManager{
		secret:     []byte(secret),
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
		now:        time.Now,
	}
}

func (m *TokenManager) Issue(userID string, role Role) (accessToken string, refreshToken string, err error) {
	if userID == "" {
		return "", "", ErrInvalidToken
	}
	if !IsValidRole(role) {
		return "", "", ErrInvalidRole
	}

	accessToken, err = m.sign(userID, role, "access", m.now().Add(m.accessTTL))
	if err != nil {
		return "", "", err
	}
	refreshToken, err = m.sign(userID, role, "refresh", m.now().Add(m.refreshTTL))
	if err != nil {
		return "", "", err
	}
	return accessToken, refreshToken, nil
}

func (m *TokenManager) ParseAccessToken(token string) (*Claims, error) {
	return m.parse(token, "access")
}

func (m *TokenManager) ParseRefreshToken(token string) (*Claims, error) {
	return m.parse(token, "refresh")
}

func (m *TokenManager) sign(userID string, role Role, tokenType string, expiresAt time.Time) (string, error) {
	claims := Claims{
		UserID: userID,
		Role:   role,
		Type:   tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			ID:        uuid.NewString(),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(m.now()),
			NotBefore: jwt.NewNumericDate(m.now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.secret)
}

func (m *TokenManager) parse(raw string, expectedType string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(raw, &Claims{}, func(token *jwt.Token) (any, error) {
		if token.Method.Alg() != jwt.SigningMethodHS256.Alg() {
			return nil, ErrInvalidToken
		}
		return m.secret, nil
	})
	if err != nil {
		return nil, ErrInvalidToken
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}
	if claims.Type != expectedType || claims.UserID == "" || !IsValidRole(claims.Role) {
		return nil, ErrInvalidToken
	}
	return claims, nil
}
