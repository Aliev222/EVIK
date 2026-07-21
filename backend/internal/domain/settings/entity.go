package settings

import (
	"context"
	"log"
	"strconv"
	"time"
)

type Setting struct {
	Key         string    `json:"key"`
	Value       any       `json:"value"`
	Description string    `json:"description"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type Repository interface {
	List(ctx context.Context) ([]Setting, error)
	Upsert(ctx context.Context, key string, value any) error
}

func GetInt(list []Setting, key string, fallback int) int {
	for _, s := range list {
		if s.Key != key {
			continue
		}
		switch v := s.Value.(type) {
		case float64:
			return int(v)
		case string:
			n, err := strconv.ParseInt(v, 10, 64)
			if err == nil {
				return int(n)
			}
			f, err := strconv.ParseFloat(v, 64)
			if err == nil {
				return int(f)
			}
		}
		log.Printf("WARN: %s invalid value (%T=%v), using fallback %d", key, s.Value, s.Value, fallback)
		return fallback
	}
	log.Printf("WARN: %s not found in settings, using fallback %d", key, fallback)
	return fallback
}
