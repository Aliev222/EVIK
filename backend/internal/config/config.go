package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr      string
	PostgresDSN   string
	RedisAddr     string
	RedisPassword string
	RedisURL      string
	JWTSecret     string
	AccessTTL     time.Duration
	RefreshTTL    time.Duration
}

func MustLoad() Config {
	httpAddr := getEnv("HTTP_ADDR", "")
	if httpAddr == "" {
		httpAddr = ":" + getEnv("PORT", "8080")
	}

	return Config{
		HTTPAddr:      httpAddr,
		PostgresDSN:   normalizePostgresDSN(getEnv("POSTGRES_DSN", getEnv("DATABASE_URL", "postgres://evik:evik@localhost:5432/evik?sslmode=disable"))),
		RedisAddr:     getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),
		RedisURL:      getEnv("REDIS_URL", ""),
		JWTSecret:     getEnv("JWT_SECRET", "evik-dev-insecure-secret"),
		AccessTTL:     getEnvDurationMinutes("JWT_ACCESS_TTL_MINUTES", 15),
		RefreshTTL:    getEnvDurationHours("JWT_REFRESH_TTL_HOURS", 168),
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
