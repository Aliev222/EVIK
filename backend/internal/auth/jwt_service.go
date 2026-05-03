package auth

import (
	"context"
	"fmt"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type JWTService struct {
	accessSecret  []byte
	refreshSecret []byte
	redis         *redis.Client
}

type TokenPair struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

// Claims структура перенесена в tokens.go чтобы избежать дублирования

type RefreshClaims struct {
	UserID string `json:"sub"`
	jwt.RegisteredClaims
}

func NewJWTService(accessSecret, refreshSecret []byte, redisClient *redis.Client) *JWTService {
	return &JWTService{
		accessSecret:  accessSecret,
		refreshSecret: refreshSecret,
		redis:         redisClient,
	}
}

func (j *JWTService) GenerateTokenPair(ctx context.Context, userID, role, phone string) (*TokenPair, error) {
	now := time.Now()
	accessExp := now.Add(1 * time.Hour)        // 1 hour access token
	refreshExp := now.Add(30 * 24 * time.Hour) // 30 days refresh token

	// Generate access token
	accessClaims := &Claims{
		UserID: userID,
		Role:   role,
		Phone:  phone,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(accessExp),
			IssuedAt:  jwt.NewNumericDate(now),
			Subject:   userID,
			Issuer:    "evik-api",
		},
	}

	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessTokenString, err := accessToken.SignedString(j.accessSecret)
	if err != nil {
		return nil, fmt.Errorf("failed to sign access token: %w", err)
	}

	// Generate refresh token
	refreshID := uuid.New().String()
	refreshClaims := &RefreshClaims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(refreshExp),
			IssuedAt:  jwt.NewNumericDate(now),
			Subject:   userID,
			ID:        refreshID,
			Issuer:    "evik-api",
		},
	}

	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshTokenString, err := refreshToken.SignedString(j.refreshSecret)
	if err != nil {
		return nil, fmt.Errorf("failed to sign refresh token: %w", err)
	}

	// Store refresh token in Redis
	key := fmt.Sprintf("refresh_token:%s", refreshID)
	err = j.redis.Set(ctx, key, userID, 30*24*time.Hour).Err()
	if err != nil {
		return nil, fmt.Errorf("failed to store refresh token: %w", err)
	}

	return &TokenPair{
		AccessToken:  accessTokenString,
		RefreshToken: refreshTokenString,
		ExpiresAt:    accessExp,
	}, nil
}

func (j *JWTService) ValidateAccessToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return j.accessSecret, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, fmt.Errorf("invalid token")
}

func (j *JWTService) RefreshTokens(ctx context.Context, refreshTokenString string) (*TokenPair, error) {
	// Parse refresh token
	token, err := jwt.ParseWithClaims(refreshTokenString, &RefreshClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return j.refreshSecret, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to parse refresh token: %w", err)
	}

	claims, ok := token.Claims.(*RefreshClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid refresh token")
	}

	// Check if refresh token exists in Redis
	key := fmt.Sprintf("refresh_token:%s", claims.ID)
	userID, err := j.redis.Get(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("refresh token not found or expired: %w", err)
	}

	if userID != claims.UserID {
		return nil, fmt.Errorf("refresh token user mismatch")
	}

	// Delete old refresh token
	j.redis.Del(ctx, key)

	// TODO: Get user role and phone from database
	// For now, using placeholder values
	role := "client" // Should be fetched from database
	phone := ""      // Should be fetched from database

	// Generate new token pair
	return j.GenerateTokenPair(ctx, userID, role, phone)
}

func (j *JWTService) RevokeRefreshToken(ctx context.Context, refreshTokenString string) error {
	token, err := jwt.ParseWithClaims(refreshTokenString, &RefreshClaims{}, func(token *jwt.Token) (interface{}, error) {
		return j.refreshSecret, nil
	})

	if err != nil {
		return fmt.Errorf("failed to parse refresh token: %w", err)
	}

	if claims, ok := token.Claims.(*RefreshClaims); ok {
		key := fmt.Sprintf("refresh_token:%s", claims.ID)
		j.redis.Del(ctx, key)
	}

	return nil
}