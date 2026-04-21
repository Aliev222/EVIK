package config

import (
	"fmt"
	"net/url"
	"os"
	"strings"
)

type Config struct {
	HTTPAddr      string
	PostgresDSN   string
	RedisAddr     string
	RedisPassword string
	RedisURL      string
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
