package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	evik "evik/backend"
	"evik/backend/internal/app"
	"evik/backend/internal/config"

	_ "evik/backend/docs"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

// @title           Tow Truck Backend API
// @version         1.0
// @description     Tow truck marketplace API — auth, orders, drivers, payments, payouts, admin, reviews, routing, pricing, cities, webhooks, real-time.
// @BasePath        /api/v1
//
// @securityDefinitions.apikey  BearerAuth
// @in                          header
// @name                        Authorization
// @description                 JWT access token. Format: "Bearer {token}"

func main() {
	cfg := config.MustLoad()
	logger := log.New(os.Stdout, "[evik] ", log.LstdFlags|log.Lshortfile)

	if err := runMigrations(cfg.PostgresDSN, logger); err != nil {
		logger.Fatalf("migrations failed: %v", err)
	}

	container, err := app.NewContainer(cfg, logger)
	if err != nil {
		logger.Fatalf("bootstrap failed: %v", err)
	}
	defer container.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           container.Router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go container.Scheduler.Run(ctx)
	go container.ExpansionScheduler.Run(ctx)
	container.RateLimiter.StartCleanup(ctx)

	go func() {
		logger.Printf("http server started on %s", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatalf("http server failed: %v", err)
		}
	}()

	<-ctx.Done()
	stop()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Printf("shutdown error: %v", err)
	}
}

func runMigrations(dsn string, logger *log.Logger) error {
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return err
	}
	defer db.Close()

	pingCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		return err
	}

	goose.SetBaseFS(evik.EmbedMigrations)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}

	logger.Printf("running database migrations...")
	if err := goose.Up(db, "migrations"); err != nil {
		return err
	}
	logger.Printf("migrations applied successfully")
	return nil
}
