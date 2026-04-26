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

	"evik/backend/internal/auth"
	"evik/backend/internal/config"
	domainmatching "evik/backend/internal/domain/matching"
	"evik/backend/internal/infrastructure/postgres"
	redisinfra "evik/backend/internal/infrastructure/redis"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	httptransport "evik/backend/internal/transport/http"
	wstransport "evik/backend/internal/transport/ws"
	driveruc "evik/backend/internal/usecase/driver"
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
	if err := ensureSchema(db); err != nil {
		return nil, err
	}

	redisOptions := &redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	}
	if cfg.RedisURL != "" {
		parsedOptions, err := redis.ParseURL(cfg.RedisURL)
		if err != nil {
			return nil, err
		}
		redisOptions = parsedOptions
	}
	rdb := redis.NewClient(redisOptions)
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		return nil, err
	}

	orderRepo := postgres.NewOrderRepository(db)
	driverRepo := postgres.NewDriverRepository(db)
	locationRepo := redisinfra.NewLocationStore(rdb)
	matchingService := domainmatching.NewNearestMatchingService(locationRepo, driverRepo)
	eventPublisher := redisinfra.NewOrderEventPublisher(rdb, "orders:status")

	clock := stdClock{}
	idGen := uuidGenerator{}
	appLogger := stdLogger{logger: logger}

	matcher := matchinguc.NewFinder(orderRepo, driverRepo, matchingService, eventPublisher, clock)
	createUC := orderuc.NewCreateOrderUseCase(orderRepo, matcher, eventPublisher, clock, idGen, appLogger)
	acceptUC := orderuc.NewAcceptOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	updateUC := orderuc.NewUpdateStatusUseCase(orderRepo, driverRepo, eventPublisher, clock)
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	setDriverStatusUC := driveruc.NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, eventPublisher, clock, appLogger)

	orderHandler := httptransport.NewOrderHandler(createUC, acceptUC, updateUC, cancelUC, orderRepo)
	driverHandler := httptransport.NewDriverHandler(setDriverStatusUC, driverRepo, locationRepo)
	tokenManager := auth.NewTokenManager(cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	authHandler := httptransport.NewAuthHandler(tokenManager)
	hub := wsinfra.NewHub()
	go hub.Run()
	wsHandler := wstransport.NewOrderWSHandler(hub, logger)
	eventRelay := wsinfra.NewOrderEventRelay(hub, eventPublisher)
	go eventRelay.Run(context.Background())

	router := httptransport.NewRouter(authHandler, orderHandler, driverHandler, wsHandler, tokenManager)
	return &Container{Router: router, db: db, rdb: rdb}, nil
}

func ensureSchema(db *sql.DB) error {
	const schema = `
CREATE TABLE IF NOT EXISTS orders (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	driver_id TEXT,
	pickup_lat DOUBLE PRECISION NOT NULL,
	pickup_lng DOUBLE PRECISION NOT NULL,
	dropoff_lat DOUBLE PRECISION NOT NULL,
	dropoff_lng DOUBLE PRECISION NOT NULL,
	status TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	cancelled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_orders_status_updated_at ON orders (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_user_id_updated_at ON orders (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_driver_id_updated_at ON orders (driver_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS drivers (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	status TEXT NOT NULL,
	current_order_id TEXT,
	last_seen_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_drivers_status_updated_at ON drivers (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_drivers_current_order_id ON drivers (current_order_id);
`
	_, err := db.Exec(schema)
	return err
}

func (c *Container) Close() {
	if c.db != nil {
		_ = c.db.Close()
	}
	if c.rdb != nil {
		_ = c.rdb.Close()
	}
}
