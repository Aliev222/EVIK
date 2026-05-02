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
	pricingdomain "evik/backend/internal/domain/pricing"
	routingdomain "evik/backend/internal/domain/routing"
	"evik/backend/internal/infrastructure/postgres"
	redisinfra "evik/backend/internal/infrastructure/redis"
	httpinfra "evik/backend/internal/infrastructure/http"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	httptransport "evik/backend/internal/transport/http"
	wstransport "evik/backend/internal/transport/ws"
	driveruc "evik/backend/internal/usecase/driver"
	matchinguc "evik/backend/internal/usecase/matching"
	orderuc "evik/backend/internal/usecase/order"
	paymentuc "evik/backend/internal/usecase/payment"
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

	// Optimize database connection pool
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := ensureSchema(db); err != nil {
		return nil, err
	}
	if err := ensureDefaultTariffs(db); err != nil {
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
	paymentRepo := postgres.NewPaymentRepository(db)
	pricingRepo := postgres.NewPricingRepository(db)
	adminRepo := postgres.NewAdminRepository(db)
	locationRepo := redisinfra.NewLocationStore(rdb)
	matchingService := domainmatching.NewNearestMatchingService(locationRepo, driverRepo)
	eventPublisher := redisinfra.NewOrderEventPublisher(rdb, "orders:status")

	clock := stdClock{}
	idGen := uuidGenerator{}
	appLogger := stdLogger{logger: logger}

	// Create pricing service with distance calculator
	distanceCalculator := pricingdomain.NewHaversineDistanceCalculator()
	pricingService := pricingdomain.NewService(pricingRepo, distanceCalculator, clock)

	// Create routing service with Yandex Maps
	httpClient := httpinfra.NewClient()
	routingService := routingdomain.NewYandexRoutingService(cfg.YandexAPIKey, httpClient)

	// Create payment transaction use case
	createTransactionUC := paymentuc.NewCreateTransactionUseCase(paymentRepo, clock, idGen)

	matcher := matchinguc.NewFinder(orderRepo, driverRepo, matchingService, eventPublisher, clock)
	createUC := orderuc.NewCreateOrderUseCase(orderRepo, matcher, pricingService, createTransactionUC, eventPublisher, clock, idGen, appLogger)
	acceptUC := orderuc.NewAcceptOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	updateUC := orderuc.NewUpdateStatusUseCase(orderRepo, driverRepo, eventPublisher, clock)
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	setDriverStatusUC := driveruc.NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, eventPublisher, clock, appLogger)

	orderHandler := httptransport.NewOrderHandler(createUC, acceptUC, updateUC, cancelUC, orderRepo)
	driverHandler := httptransport.NewDriverHandler(setDriverStatusUC, driverRepo, locationRepo)
	paymentHandler := httptransport.NewPaymentHandler(paymentRepo, idGen, clock)
	pricingHandler := httptransport.NewPricingHandler(pricingService)
	routingHandler := httptransport.NewRoutingHandler(routingService, orderRepo)
	adminHandler := httptransport.NewAdminHandler(
		adminRepo,
		driverRepo,
		locationRepo,
		idGen,
		clock,
		httptransport.DocumentStorageConfig{
			Endpoint:  cfg.S3Endpoint,
			Region:    cfg.S3Region,
			Bucket:    cfg.S3Bucket,
			AccessKey: cfg.S3AccessKey,
			SecretKey: cfg.S3SecretKey,
		},
	)
	tokenManager := auth.NewTokenManager(cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	authHandler := httptransport.NewAuthHandler(tokenManager, cfg.AdminUserID, cfg.AdminPassword)
	hub := wsinfra.NewHub()
	go hub.Run()
	wsHandler := wstransport.NewOrderWSHandler(hub, cfg.AllowedOrigins, logger, tokenManager)
	eventRelay := wsinfra.NewOrderEventRelay(hub, eventPublisher, logger)
	go eventRelay.Run(context.Background())

	router := httptransport.NewRouter(authHandler, orderHandler, driverHandler, paymentHandler, pricingHandler, routingHandler, adminHandler, wsHandler, tokenManager, cfg.AllowedOrigins)
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
	tow_truck_type TEXT NOT NULL DEFAULT 'standard',
	status TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	cancelled_at TIMESTAMPTZ
);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS tow_truck_type TEXT NOT NULL DEFAULT 'standard';

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

CREATE TABLE IF NOT EXISTS payment_methods (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	brand TEXT NOT NULL,
	last4 TEXT NOT NULL,
	exp_month INTEGER NOT NULL,
	exp_year INTEGER NOT NULL,
	holder TEXT NOT NULL,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_user_id ON payment_methods (user_id, is_default DESC, created_at DESC);

CREATE TABLE IF NOT EXISTS payment_transactions (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	order_id TEXT NOT NULL,
	title TEXT NOT NULL,
	amount BIGINT NOT NULL,
	status TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_user_id_created_at ON payment_transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_order_id ON payment_transactions (order_id);

CREATE TABLE IF NOT EXISTS pricing_tariffs (
	id TEXT PRIMARY KEY,
	tow_truck_type TEXT NOT NULL,
	base_price BIGINT NOT NULL,
	price_per_km BIGINT NOT NULL,
	minimum_price BIGINT NOT NULL,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pricing_tariffs_type_active ON pricing_tariffs (tow_truck_type, is_active);

CREATE TABLE IF NOT EXISTS driver_verifications (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	full_name TEXT NOT NULL,
	phone TEXT NOT NULL DEFAULT '',
	city TEXT NOT NULL DEFAULT '',
	vehicle_model TEXT NOT NULL,
	vehicle_plate TEXT NOT NULL,
	vehicle_type TEXT NOT NULL,
	status TEXT NOT NULL,
	risk TEXT NOT NULL DEFAULT 'low',
	documents_json TEXT NOT NULL DEFAULT '[]',
	signals_json TEXT NOT NULL DEFAULT '[]',
	decision_reason TEXT,
	reviewed_by TEXT,
	reviewed_at TIMESTAMPTZ,
	submitted_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_verifications_status_submitted_at ON driver_verifications (status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_verifications_user_id ON driver_verifications (user_id);

CREATE TABLE IF NOT EXISTS driver_reviews (
	id TEXT PRIMARY KEY,
	order_id TEXT NOT NULL,
	driver_id TEXT NOT NULL,
	client_id TEXT NOT NULL,
	stars INTEGER NOT NULL,
	text TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_reviews_driver_created_at ON driver_reviews (driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_reviews_created_at ON driver_reviews (created_at DESC);

CREATE TABLE IF NOT EXISTS moderation_audit_log (
	id TEXT PRIMARY KEY,
	entity_type TEXT NOT NULL,
	entity_id TEXT NOT NULL,
	action TEXT NOT NULL,
	reason TEXT NOT NULL DEFAULT '',
	moderator_id TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_moderation_audit_entity_created_at ON moderation_audit_log (entity_type, entity_id, created_at DESC);
`
	_, err := db.Exec(schema)
	return err
}

func ensureDefaultTariffs(db *sql.DB) error {
	const insertTariffs = `
	INSERT INTO pricing_tariffs (id, tow_truck_type, base_price, price_per_km, minimum_price, is_active, created_at, updated_at)
	VALUES
		('tariff-winch', 'winch', 250000, 5000, 250000, true, NOW(), NOW()),
		('tariff-platform', 'platform', 300000, 6000, 300000, true, NOW(), NOW()),
		('tariff-manipulator', 'manipulator', 400000, 8000, 400000, true, NOW(), NOW())
	ON CONFLICT (id) DO UPDATE SET
		base_price = EXCLUDED.base_price,
		price_per_km = EXCLUDED.price_per_km,
		minimum_price = EXCLUDED.minimum_price,
		is_active = EXCLUDED.is_active,
		updated_at = NOW();
	`
	_, err := db.Exec(insertTariffs)
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
