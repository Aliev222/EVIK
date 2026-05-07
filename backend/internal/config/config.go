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
	HTTPAddr       string
	AppEnv         string
	PostgresDSN    string
	RedisAddr      string
	RedisPassword  string
	RedisURL       string
	JWTSecret      string
	AccessTTL      time.Duration
	RefreshTTL     time.Duration
	AllowedOrigins []string
	AdminUserID    string
	AdminPassword  string
	S3Endpoint     string
	S3Region       string
	S3Bucket       string
	S3AccessKey    string
	S3SecretKey    string
	ProMapsRoadKey string
}

func MustLoad() Config {
	httpAddr := getEnv("HTTP_ADDR", "")
	if httpAddr == "" {
		httpAddr = ":" + getEnv("PORT", "8080")
	}

	cfg := Config{
		HTTPAddr:       httpAddr,
		AppEnv:         getEnv("APP_ENV", "development"),
		PostgresDSN:    normalizePostgresDSN(getEnv("POSTGRES_DSN", getEnv("DATABASE_URL", "postgres://evik:evik@localhost:5432/evik?sslmode=disable"))),
		RedisAddr:      getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:  getEnv("REDIS_PASSWORD", ""),
		RedisURL:       getEnv("REDIS_URL", ""),
		JWTSecret:      getEnv("JWT_SECRET", "evik-dev-insecure-secret"),
		AccessTTL:      getEnvDurationMinutes("JWT_ACCESS_TTL_MINUTES", 15),
		RefreshTTL:     getEnvDurationHours("JWT_REFRESH_TTL_HOURS", 168),
		AllowedOrigins: getAllowedOrigins(),
		AdminUserID:    getEnv("ADMIN_USER_ID", "admin"),
		AdminPassword:  getEnv("ADMIN_PASSWORD", ""),
		S3Endpoint:     getEnv("S3_ENDPOINT", ""),
		S3Region:       getEnv("S3_REGION", "ru-1"),
		S3Bucket:       getEnv("S3_BUCKET", ""),
		S3AccessKey:    getEnv("S3_ACCESS_KEY", ""),
		S3SecretKey:    getEnv("S3_SECRET_KEY", ""),
		ProMapsRoadKey: getEnv("PROMAPS_ROAD_API_KEY", ""),
	}
	validateProductionConfig(cfg)
	return cfg
}

func (c Config) IsProduction() bool {
	return strings.EqualFold(c.AppEnv, "production")
}

func validateProductionConfig(cfg Config) {
	if !cfg.IsProduction() {
		return
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
	if cfg.S3Endpoint == "" || cfg.S3Bucket == "" || cfg.S3AccessKey == "" || cfg.S3SecretKey == "" {
		missing = append(missing, "S3_ENDPOINT/S3_BUCKET/S3_ACCESS_KEY/S3_SECRET_KEY")
	}
	if len(missing) > 0 {
		log.Fatalf("invalid production config: %s", strings.Join(missing, ", "))
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
