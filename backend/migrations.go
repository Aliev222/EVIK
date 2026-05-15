package backend

import "embed"

// EmbedMigrations contains all SQL migration files from backend/migrations/
// embedded into the application binary. The migrations are applied at
// startup via goose in cmd/app/main.go.
//
//go:embed migrations/*.sql
var EmbedMigrations embed.FS
