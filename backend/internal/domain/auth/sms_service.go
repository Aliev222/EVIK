package auth

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/google/uuid"
)

type SMSProvider interface {
	SendSMS(phone, message string) error
}

type SMSService struct {
	smsProvider SMSProvider
	redis       *redis.Client
}

type VerificationResult struct {
	VerificationID string
	ExpiresAt      time.Time
}

func NewSMSService(smsProvider SMSProvider, redisClient *redis.Client) *SMSService {
	return &SMSService{
		smsProvider: smsProvider,
		redis:       redisClient,
	}
}

func (s *SMSService) SendVerificationCode(ctx context.Context, phone string) (*VerificationResult, error) {
	// Generate verification ID
	verificationID := uuid.New().String()

	// Generate 4-digit code
	code, err := s.generateCode()
	if err != nil {
		return nil, fmt.Errorf("failed to generate code: %w", err)
	}

	// Store in Redis with 5 minute TTL
	key := fmt.Sprintf("verification:%s", verificationID)
	err = s.redis.Set(ctx, key, code, 5*time.Minute).Err()
	if err != nil {
		return nil, fmt.Errorf("failed to store verification code: %w", err)
	}

	// Send SMS
	message := fmt.Sprintf("EVIK: Ваш код подтверждения %s", code)
	err = s.smsProvider.SendSMS(phone, message)
	if err != nil {
		// Clean up Redis if SMS failed
		s.redis.Del(ctx, key)
		return nil, fmt.Errorf("failed to send SMS: %w", err)
	}

	return &VerificationResult{
		VerificationID: verificationID,
		ExpiresAt:      time.Now().Add(5 * time.Minute),
	}, nil
}

func (s *SMSService) VerifyCode(ctx context.Context, verificationID, code string) (bool, error) {
	key := fmt.Sprintf("verification:%s", verificationID)

	// Get stored code from Redis
	storedCode, err := s.redis.Get(ctx, key).Result()
	if err == redis.Nil {
		return false, nil // Code expired or not found
	}
	if err != nil {
		return false, fmt.Errorf("failed to get verification code: %w", err)
	}

	// Compare codes
	if storedCode != code {
		return false, nil
	}

	// Delete used code
	s.redis.Del(ctx, key)

	return true, nil
}

func (s *SMSService) generateCode() (string, error) {
	// Generate random number 1000-9999
	max := big.NewInt(9000) // 9999 - 1000 = 8999
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}

	code := n.Int64() + 1000 // Add 1000 to get range 1000-9999
	return fmt.Sprintf("%04d", code), nil
}