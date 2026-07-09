//go:build integration

package postgres_test

import (
	"context"
	"crypto/rand"
	"database/sql"
	"fmt"
	"testing"

	evik "evik/backend"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

func setupTestDB(t *testing.T) (*sql.DB, func()) {
	t.Helper()

	ctx := context.Background()

	pgContainer, err := postgres.Run(ctx,
		"docker.io/postgres:16-alpine",
		postgres.WithDatabase("evik_test"),
		postgres.WithUsername("evik"),
		postgres.WithPassword("evik"),
		postgres.WithSQLDriver("pgx"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).
				WithStartupTimeout(60_000_000_000),
		),
	)
	if err != nil {
		t.Fatalf("failed to start postgres container: %v", err)
	}

	connStr, err := pgContainer.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("failed to get connection string: %v", err)
	}

	db, err := sql.Open("pgx", connStr)
	if err != nil {
		t.Fatalf("failed to open database: %v", err)
	}

	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("failed to ping database: %v", err)
	}

	goose.SetBaseFS(evik.EmbedMigrations)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatalf("failed to set goose dialect: %v", err)
	}

	if err := goose.Up(db, "migrations"); err != nil {
		t.Fatalf("failed to run migrations: %v", err)
	}

	cleanup := func() {
		db.Close()
		if err := testcontainers.TerminateContainer(pgContainer); err != nil {
			t.Logf("failed to terminate container: %v", err)
		}
	}

	return db, cleanup
}

func seedUser(t *testing.T, db *sql.DB, id, role string) {
	t.Helper()
	if _, err := db.Exec(`INSERT INTO users (id, phone, full_name, role, status, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', NOW(), NOW())`,
		id, "7999"+id[len(id)-4:], "User "+role, role); err != nil {
		t.Fatalf("insert user %s: %v", id, err)
	}
}

func seedOrderRaw(t *testing.T, db *sql.DB, id, userID string) {
	t.Helper()
	if _, err := db.Exec(`
INSERT INTO orders (id, user_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, tow_truck_type, status, price_total, created_at, updated_at)
VALUES ($1, $2, 42.0, 47.5, 42.1, 47.6, 'winch', 'created', 500000, NOW(), NOW())`,
		id, userID); err != nil {
		t.Fatalf("insert order %s: %v", id, err)
	}
}

func seedDriver(t *testing.T, db *sql.DB, id string) {
	t.Helper()
	if _, err := db.Exec(`INSERT INTO drivers (id, user_id, status, last_seen_at, updated_at) VALUES ($1, $2, 'online', NOW(), NOW())`,
		id, id); err != nil {
		t.Fatalf("insert driver %s: %v", id, err)
	}
}

func uuid() string {
	b := make([]byte, 16)
	rand.Read(b)
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

func truncateAll(t *testing.T, db *sql.DB) {
	t.Helper()

	tables := []string{
		"wallet_transactions",
		"wallet_transaction_locks",
		"payouts",
		"driver_payout_methods",
		"subscriptions",
		"refunds",
		"payments",
		"payment_methods",
		"payment_webhooks",
		"driver_reviews",
		"orders",
		"driver_tax_profiles",
		"driver_documents",
		"driver_verifications",
		"driver_wallets",
		"drivers",
		"user_device_tokens",
		"user_refresh_sessions",
		"phone_otps",
		"users",
	}

	for _, table := range tables {
		if _, err := db.Exec("DELETE FROM " + table); err != nil {
			t.Fatalf("failed to truncate %s: %v", table, err)
		}
	}
}