package postgres

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"evik/backend/internal/domain/settings"
)

type SettingsRepository struct {
	db *sql.DB
}

func NewSettingsRepository(db *sql.DB) *SettingsRepository {
	return &SettingsRepository{db: db}
}

func (r *SettingsRepository) List(ctx context.Context) ([]settings.Setting, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT key, value, description, updated_at FROM platform_settings ORDER BY key`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []settings.Setting
	for rows.Next() {
		var s settings.Setting
		var rawValue []byte
		if err := rows.Scan(&s.Key, &rawValue, &s.Description, &s.UpdatedAt); err != nil {
			return nil, err
		}
		json.Unmarshal(rawValue, &s.Value)
		out = append(out, s)
	}
	return out, rows.Err()
}

func (r *SettingsRepository) Upsert(ctx context.Context, key string, value any) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	_, err = r.db.ExecContext(ctx, `
		INSERT INTO platform_settings (key, value, description, updated_at)
		VALUES ($1, $2, '', $3)
		ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = $3
	`, key, string(raw), time.Now().UTC())
	return err
}
