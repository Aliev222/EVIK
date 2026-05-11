package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"evik/backend/internal/app"
	"evik/backend/internal/config"
)

func main() {
	cfg := config.MustLoad()
	logger := log.New(os.Stdout, "[evik] ", log.LstdFlags|log.Lshortfile)

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
