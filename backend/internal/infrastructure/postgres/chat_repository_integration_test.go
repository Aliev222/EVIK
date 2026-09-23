//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	evik "evik/backend"
	chatdomain "evik/backend/internal/domain/chat"
	postgresrepo "evik/backend/internal/infrastructure/postgres"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

func openChatIntegrationDB(t *testing.T) (*sql.DB, func()) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is required for chat integration tests")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.PingContext(context.Background()); err != nil {
		db.Close()
		t.Fatal(err)
	}
	goose.SetBaseFS(evik.EmbedMigrations)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("postgres"); err != nil {
		db.Close()
		t.Fatal(err)
	}
	if err := goose.Up(db, "migrations"); err != nil {
		db.Close()
		t.Fatal(err)
	}
	return db, func() { db.Close() }
}

func seedChatFixture(t *testing.T, db *sql.DB) (string, string, string) {
	t.Helper()
	client, driver, order := "chat-client", "chat-driver", "chat-order"
	_, _ = db.Exec(`DELETE FROM chat_messages WHERE order_id=$1`, order)
	_, _ = db.Exec(`DELETE FROM orders WHERE id=$1`, order)
	for _, u := range []struct{ id, role string }{{client, "client"}, {driver, "driver"}} {
		_, _ = db.Exec(`DELETE FROM users WHERE id=$1`, u.id)
		if _, err := db.Exec(`INSERT INTO users (id, phone, full_name, role, status, created_at, updated_at) VALUES ($1,$2,$3,$4,'active',NOW(),NOW())`, u.id, "+7999000000"+u.id[len(u.id)-1:], u.id, u.role); err != nil {
			t.Fatal(err)
		}
	}
	_, _ = db.Exec(`DELETE FROM drivers WHERE id=$1`, driver)
	if _, err := db.Exec(`INSERT INTO drivers (id,user_id,status,last_seen_at,updated_at) VALUES ($1,$1,'online',NOW(),NOW())`, driver); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO orders (id,user_id,driver_id,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,tow_truck_type,status,price_total,created_at,updated_at) VALUES ($1,$2,$3,42,47,42.1,47.1,'winch','accepted',100,$4,$4)`, order, client, driver, time.Now()); err != nil {
		t.Fatal(err)
	}
	return client, driver, order
}

func TestChatRepositoryIntegrationCreateReplayAndPoolSafety(t *testing.T) {
	db, cleanup := openChatIntegrationDB(t)
	defer cleanup()
	client, driver, order := seedChatFixture(t, db)
	repo := postgresrepo.NewChatRepository(db)
	first, err := repo.Create(context.Background(), order, client, "c1", "hello")
	if err != nil {
		t.Fatal(err)
	}
	replay, err := repo.Create(context.Background(), order, client, "c1", "changed")
	if err != nil || replay.ID != first.ID || replay.Text != "hello" {
		t.Fatalf("replay=%+v err=%v", replay, err)
	}
	if _, err := repo.Create(context.Background(), order, driver, "d1", "reply"); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Create(context.Background(), order, "stranger", "x", "no"); !errors.Is(err, chatdomain.ErrForbidden) {
		t.Fatalf("expected forbidden, got %v", err)
	}

	db.SetMaxOpenConns(1)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if _, err := repo.Create(ctx, order, "stranger", "pool", "no"); !errors.Is(err, chatdomain.ErrForbidden) {
		t.Fatalf("pool-safe forbidden=%v", err)
	}

	time.Sleep(800 * time.Millisecond)
	db.SetMaxOpenConns(8)
	var wg sync.WaitGroup
	results := make(chan string, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			m, e := repo.Create(context.Background(), order, driver, "concurrent", "same")
			if e == nil {
				results <- m.ID
			}
		}()
	}
	wg.Wait()
	close(results)
	ids := map[string]struct{}{}
	for id := range results {
		ids[id] = struct{}{}
	}
	if len(ids) != 1 {
		t.Fatalf("concurrent replay created %d records: %v", len(ids), ids)
	}
}

func TestChatRepositoryIntegrationPaginationAndCursorValidation(t *testing.T) {
	db, cleanup := openChatIntegrationDB(t)
	defer cleanup()
	client, _, order := seedChatFixture(t, db)
	repo := postgresrepo.NewChatRepository(db)
	for i := 0; i < 3; i++ {
		time.Sleep(800 * time.Millisecond)
		if _, err := repo.Create(context.Background(), order, client, "page"+string(rune('a'+i)), "message"); err != nil {
			t.Fatal(err)
		}
	}
	page, err := repo.List(context.Background(), order, client, "", 2)
	if err != nil || len(page) != 2 {
		t.Fatalf("page len=%d err=%v", len(page), err)
	}
	if _, err := repo.List(context.Background(), order, client, "missing", 2); !errors.Is(err, chatdomain.ErrInvalidCursor) {
		t.Fatalf("cursor error=%v", err)
	}
}
