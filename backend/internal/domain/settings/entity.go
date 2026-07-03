package settings

import (
	"context"
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
