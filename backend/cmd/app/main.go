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

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           container.Router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		logger.Printf("http server started on %s", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatalf("http server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Printf("shutdown error: %v", err)
	}
}
