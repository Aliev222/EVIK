package config

import "os"

type Config struct {
	HTTPAddr      string
	PostgresDSN   string
	RedisAddr     string
	RedisPassword string
}

func MustLoad() Config {
	return Config{
		HTTPAddr:      getEnv("HTTP_ADDR", ":8080"),
		PostgresDSN:   getEnv("POSTGRES_DSN", "postgres://evik:evik@localhost:5432/evik?sslmode=disable"),
		RedisAddr:     getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
