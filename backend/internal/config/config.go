package config

import (
	"fmt"
	"log"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr                   string
	AppEnv                     string
	PostgresDSN                string
	RedisAddr                  string
	RedisPassword              string
	RedisURL                   string
	JWTSecret                  string
	AccessTTL                  time.Duration
	RefreshTTL                 time.Duration
	AllowedOrigins             []string
	AdminUserID                string
	AdminPassword              string
	S3Endpoint                 string
	S3Region                   string
	S3Bucket                   string
	S3AccessKey                string
	S3SecretKey                string
	S3PublicBaseURL            string
	OSRMBaseURL                string
	YooKassaShopID             string
	YooKassaSecret             string
	YooKassaReturnURL          string
	YooKassaWebhookSecret      string
	YooKassaPayoutGatewayID    string
	YooKassaPayoutSecret       string
	YooKassaPayoutMode         string
	YooKassaStubMode           bool
	FinancePendingHoldSeconds  int
	MinimumWithdrawalKopecks   int64
	BalanceReleaseInterval          time.Duration
	OrderExpansionCheckInterval     time.Duration
	OrderExpansionDelay             time.Duration
	OrderExpansionRadiusKM          float64
	DriverSubscriptionRequired      bool
	DriverGateBypass           bool
	ExposeSwagger              bool
	FirebaseCredentialsJSON    string
	OTPFixedCode               string
}

func MustLoad() Config {
	httpAddr := getEnv("HTTP_ADDR", "")
	if httpAddr == "" {
		httpAddr = ":" + getEnv("PORT", "8080")
	}

	otpFixedCode := getFixedOTPCode()
	if otpFixedCode != "" {
		log.Printf("WARN: OTP_FIXED_CODE is set — all OTP verifications will use fixed code. This MUST NOT be used in production!")
	}

	appEnv := getEnv("APP_ENV", "development")
	isProduction := strings.EqualFold(appEnv, "production")

	driverGateBypassDefault := otpFixedCode != "" && !isProduction

	cfg := Config{
		HTTPAddr:                   httpAddr,
		AppEnv:                     appEnv,
		PostgresDSN:                normalizePostgresDSN(getEnv("POSTGRES_DSN", getEnv("DATABASE_URL", "postgres://evik:evik@localhost:5432/evik?sslmode=disable"))),
		RedisAddr:                  getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:              getEnv("REDIS_PASSWORD", ""),
		RedisURL:                   getEnv("REDIS_URL", ""),
		JWTSecret:                  getEnv("JWT_SECRET", "evik-dev-insecure-secret"),
		AccessTTL:                  getEnvDurationMinutes("JWT_ACCESS_TTL_MINUTES", 15),
		RefreshTTL:                 getEnvDurationHours("JWT_REFRESH_TTL_HOURS", 168),
		AllowedOrigins:             getAllowedOrigins(),
		AdminUserID:                getEnv("ADMIN_USER_ID", "admin"),
		AdminPassword:              getEnv("ADMIN_PASSWORD", ""),
		S3Endpoint:                 getEnv("S3_ENDPOINT", ""),
		S3Region:                   getEnv("S3_REGION", "ru-1"),
		S3Bucket:                   getEnv("S3_BUCKET", ""),
		S3AccessKey:                getEnv("S3_ACCESS_KEY", ""),
		S3SecretKey:                getEnv("S3_SECRET_KEY", ""),
		S3PublicBaseURL:            getEnv("S3_PUBLIC_BASE_URL", ""),
		OSRMBaseURL:                getEnv("OSRM_BASE_URL", "https://router.project-osrm.org"),
		YooKassaShopID:             getEnv("YOOKASSA_SHOP_ID", ""),
		YooKassaSecret:             getEnv("YOOKASSA_SECRET_KEY", ""),
		YooKassaReturnURL:          getEnv("YOOKASSA_RETURN_URL", "https://evik-web.onrender.com/payment-return"),
		YooKassaWebhookSecret:      getEnv("YOOKASSA_WEBHOOK_SECRET", ""),
		YooKassaPayoutGatewayID:    getEnv("YOOKASSA_PAYOUT_GATEWAY_ID", ""),
		YooKassaPayoutSecret:       getEnv("YOOKASSA_PAYOUT_SECRET_KEY", ""),
		YooKassaPayoutMode:         getEnv("YOOKASSA_PAYOUT_MODE", "sandbox"),
		YooKassaStubMode:           getEnvBool("YOOKASSA_STUB_MODE", false),
		FinancePendingHoldSeconds:  getEnvInt("FINANCE_PENDING_HOLD_SECONDS", 600),
		MinimumWithdrawalKopecks:   int64(getEnvInt("MINIMUM_WITHDRAWAL_KOPECKS", 10000)),
		BalanceReleaseInterval:          getEnvDuration("EVIK_BALANCE_RELEASE_INTERVAL", 5*time.Minute),
		OrderExpansionCheckInterval:     getEnvDuration("ORDER_EXPANSION_CHECK_INTERVAL", 10*time.Second),
		OrderExpansionDelay:             getEnvDuration("ORDER_EXPANSION_DELAY", 60*time.Second),
		OrderExpansionRadiusKM:          getEnvFloat64("ORDER_EXPANSION_RADIUS_KM", 30.0),
		DriverSubscriptionRequired: getEnvBool("DRIVER_SUBSCRIPTION_REQUIRED", false),
		DriverGateBypass:           getEnvBool("DRIVER_GATE_BYPASS", driverGateBypassDefault),
		ExposeSwagger:              getEnvBool("EXPOSE_SWAGGER", false),
		FirebaseCredentialsJSON:    getEnv("FIREBASE_CREDENTIALS_JSON", ""),
		OTPFixedCode:               otpFixedCode,
	}
	validateProductionConfig(cfg)
	return cfg
}

func getFixedOTPCode() string {
	code := strings.TrimSpace(getEnv("OTP_FIXED_CODE", ""))
	if code == "" {
		return ""
	}
	if len(code) != 6 {
		log.Fatalf("invalid OTP_FIXED_CODE: must be exactly 6 digits")
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			log.Fatalf("invalid OTP_FIXED_CODE: must contain digits only")
		}
	}
	return code
}

func (c Config) IsProduction() bool {
	return strings.EqualFold(c.AppEnv, "production")
}

func validateProductionConfig(cfg Config) {
	if !cfg.IsProduction() {
		return
	}
	if cfg.OTPFixedCode != "" {
		log.Fatal("FATAL: OTP_FIXED_CODE must not be set in production. Remove it from environment.")
	}
	if cfg.DriverGateBypass {
		log.Fatal("FATAL: DRIVER_GATE_BYPASS must not be true in production.")
	}
	var missing []string
	if cfg.JWTSecret == "" || cfg.JWTSecret == "evik-dev-insecure-secret" || len(cfg.JWTSecret) < 32 {
		missing = append(missing, "JWT_SECRET(>=32 chars, not dev default)")
	}
	if len(cfg.AllowedOrigins) == 0 {
		missing = append(missing, "ALLOWED_ORIGINS")
	}
	if cfg.AdminUserID == "" {
		missing = append(missing, "ADMIN_USER_ID")
	}
	if len(cfg.AdminPassword) < 12 {
		missing = append(missing, "ADMIN_PASSWORD(>=12 chars)")
	}
	if cfg.S3Endpoint == "" || cfg.S3Bucket == "" || cfg.S3AccessKey == "" || cfg.S3SecretKey == "" || cfg.S3PublicBaseURL == "" {
		missing = append(missing, "S3_ENDPOINT/S3_BUCKET/S3_ACCESS_KEY/S3_SECRET_KEY/S3_PUBLIC_BASE_URL")
	}
	if cfg.YooKassaShopID == "" || cfg.YooKassaSecret == "" {
		missing = append(missing, "YOOKASSA_SHOP_ID/YOOKASSA_SECRET_KEY")
	}
	if len(missing) > 0 {
		log.Fatalf("invalid production config: %s", strings.Join(missing, ", "))
	}
}

func getEnvInt(key string, fallback int) int {
	raw := getEnv(key, "")
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return value
}

func getEnvBool(key string, fallback bool) bool {
	raw := strings.TrimSpace(strings.ToLower(getEnv(key, "")))
	if raw == "" {
		return fallback
	}
	switch raw {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func normalizePostgresDSN(dsn string) string {
	if strings.Contains(dsn, "sslmode=") {
		return dsn
	}
	parsed, err := url.Parse(dsn)
	if err != nil || parsed.Hostname() == "localhost" || parsed.Hostname() == "127.0.0.1" {
		return dsn
	}
	separator := "?"
	if strings.Contains(dsn, "?") {
		separator = "&"
	}
	return fmt.Sprintf("%s%ssslmode=require", dsn, separator)
}

func getEnvDurationMinutes(key string, fallbackMinutes int) time.Duration {
	raw := getEnv(key, "")
	if raw == "" {
		return time.Duration(fallbackMinutes) * time.Minute
	}
	minutes, err := strconv.Atoi(raw)
	if err != nil || minutes <= 0 {
		return time.Duration(fallbackMinutes) * time.Minute
	}
	return time.Duration(minutes) * time.Minute
}

func getEnvDurationHours(key string, fallbackHours int) time.Duration {
	raw := getEnv(key, "")
	if raw == "" {
		return time.Duration(fallbackHours) * time.Hour
	}
	hours, err := strconv.Atoi(raw)
	if err != nil || hours <= 0 {
		return time.Duration(fallbackHours) * time.Hour
	}
	return time.Duration(hours) * time.Hour
}

func getEnvFloat64(key string, fallback float64) float64 {
	raw := getEnv(key, "")
	if raw == "" {
		return fallback
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil || v <= 0 {
		return fallback
	}
	return v
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	raw := getEnv(key, "")
	if raw == "" {
		return fallback
	}
	value, err := time.ParseDuration(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func getAllowedOrigins() []string {
	originsEnv := getEnv("ALLOWED_ORIGINS", "")
	if originsEnv == "" {
		// Default allowed origins for development and production
		return []string{
			"https://evik-web.onrender.com",
			"http://localhost:3000",
			"http://127.0.0.1:3000",
			"http://localhost:8080",
			"http://127.0.0.1:8080",
		}
	}

	// Parse comma-separated origins from environment
	origins := strings.Split(originsEnv, ",")
	var trimmedOrigins []string
	for _, origin := range origins {
		trimmed := strings.TrimSpace(origin)
		if trimmed != "" {
			trimmedOrigins = append(trimmedOrigins, trimmed)
		}
	}
	return trimmedOrigins
}
