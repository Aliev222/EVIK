//go:build integration

package postgres_test

import (
	"testing"
)

func TestSetupDB_Smoke(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	var version string
	if err := db.QueryRow("SELECT version()").Scan(&version); err != nil {
		t.Fatalf("failed to query postgres version: %v", err)
	}
	t.Logf("Postgres version: %s", version)

	var tableCount int
	if err := db.QueryRow("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'").Scan(&tableCount); err != nil {
		t.Fatalf("failed to count tables: %v", err)
	}
	t.Logf("Tables created: %d", tableCount)

	if tableCount < 20 {
		t.Fatalf("expected at least 20 tables, got %d", tableCount)
	}

	truncateAll(t, db)

	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count); err != nil {
		t.Fatalf("failed to query users after truncate: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected 0 users after truncate, got %d", count)
	}
}