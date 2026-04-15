package app

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"

	"evik/backend/internal/config"
	domainmatching "evik/backend/internal/domain/matching"
	"evik/backend/internal/infrastructure/postgres"
	redisinfra "evik/backend/internal/infrastructure/redis"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	httptransport "evik/backend/internal/transport/http"
	wstransport "evik/backend/internal/transport/ws"
	matchinguc "evik/backend/internal/usecase/matching"
	orderuc "evik/backend/internal/usecase/order"
)

type Container struct {
	Router http.Handler
	db     *sql.DB
	rdb    *redis.Client
}

type stdClock struct{}

func (stdClock) Now() time.Time { return time.Now().UTC() }

type uuidGenerator struct{}

func (uuidGenerator) NewID() string { return uuid.NewString() }

type stdLogger struct{ logger *log.Logger }

func (l stdLogger) Info(msg string, keyvals ...any) {
	l.logger.Printf("INFO: %s %v", msg, keyvals)
}

func (l stdLogger) Error(msg string, err error, keyvals ...any) {
	l.logger.Printf("ERROR: %s err=%v %v", msg, err, keyvals)
}

func NewContainer(cfg config.Config, logger *log.Logger) (*Container, error) {
	db, err := sql.Open("pgx", cfg.PostgresDSN)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}

	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		return nil, err
	}

	orderRepo := postgres.NewOrderRepository(db)
	locationRepo := redisinfra.NewLocationStore(rdb)
	matchingService := domainmatching.NewNearestMatchingService(locationRepo)
	eventPublisher := redisinfra.NewOrderEventPublisher(rdb, "orders:status")

	clock := stdClock{}
	idGen := uuidGenerator{}
	appLogger := stdLogger{logger: logger}

	matcher := matchinguc.NewFinder(orderRepo, matchingService, eventPublisher, clock)
	createUC := orderuc.NewCreateOrderUseCase(orderRepo, matcher, eventPublisher, clock, idGen, appLogger)
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, eventPublisher, clock, appLogger)

	orderHandler := httptransport.NewOrderHandler(createUC, cancelUC)
	hub := wsinfra.NewHub()
	go hub.Run()
	wsHandler := wstransport.NewOrderWSHandler(hub, logger)
	eventRelay := wsinfra.NewOrderEventRelay(hub, eventPublisher)
	go eventRelay.Run(context.Background())

	router := httptransport.NewRouter(orderHandler, wsHandler)
	return &Container{Router: router, db: db, rdb: rdb}, nil
}

func (c *Container) Close() {
	if c.db != nil {
		_ = c.db.Close()
	}
	if c.rdb != nil {
		_ = c.rdb.Close()
	}
}
