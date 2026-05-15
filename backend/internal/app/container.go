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
	httpinfra "evik/backend/internal/infrastructure/http"
	"evik/backend/internal/infrastructure/postgres"
	redisinfra "evik/backend/internal/infrastructure/redis"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	httptransport "evik/backend/internal/transport/http"
	wstransport "evik/backend/internal/transport/ws"
	driveruc "evik/backend/internal/usecase/driver"
	matchinguc "evik/backend/internal/usecase/matching"
	orderuc "evik/backend/internal/usecase/order"
	paymentuc "evik/backend/internal/usecase/payment"
)

type Container struct {
	Router    http.Handler
	Scheduler *Scheduler
	db        *sql.DB
	rdb       *redis.Client
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

type yookassaProvider struct {
	client *httpinfra.YooKassaClient
}

func (p yookassaProvider) CreatePayment(ctx context.Context, req paymentuc.ProviderPaymentRequest) (*paymentuc.ProviderPaymentResponse, error) {
	res, err := p.client.CreatePayment(ctx, httpinfra.YooKassaPaymentRequest{
		Amount:         req.Amount,
		Currency:       req.Currency,
		Description:    req.Description,
		IdempotencyKey: req.IdempotencyKey,
		Metadata:       req.Metadata,
		Capture:        req.Capture,
		SaveMethod:     req.SaveMethod,
	})
	if err != nil {
		return nil, err
	}
	return &paymentuc.ProviderPaymentResponse{ID: res.ID, Status: res.Status, ConfirmationURL: res.ConfirmationURL, Paid: res.Paid}, nil
}

func (p yookassaProvider) CreatePayout(ctx context.Context, req paymentuc.ProviderPayoutRequest) (*paymentuc.ProviderPayoutResponse, error) {
	res, err := p.client.CreatePayout(ctx, httpinfra.YooKassaPayoutRequest{
		Amount:              req.Amount,
		Currency:            req.Currency,
		ProviderRecipientID: req.ProviderRecipientID,
		Description:         req.Description,
		IdempotencyKey:      req.IdempotencyKey,
	})
	if err != nil {
		return nil, err
	}
	return &paymentuc.ProviderPayoutResponse{ID: res.ID, Status: res.Status}, nil
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

	if err := EnsureSchema(db); err != nil {
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
	userRepo := postgres.NewUserRepository(db)
	serviceAreaRepo := postgres.NewServiceAreaRepository(db)
	pricingRepo := postgres.NewPricingRepository(db)
	adminRepo := postgres.NewAdminRepository(db)
	verificationRepo := postgres.NewDriverVerificationRepository(db)
	locationRepo := redisinfra.NewLocationStore(rdb)
	matchingService := domainmatching.NewNearestMatchingService(locationRepo, driverRepo)
	eventPublisher := redisinfra.NewOrderEventPublisher(rdb, "orders:status")

	clock := stdClock{}
	idGen := uuidGenerator{}
	appLogger := stdLogger{logger: logger}

	// Create pricing service with distance calculator
	distanceCalculator := pricingdomain.NewHaversineDistanceCalculator()
	pricingService := pricingdomain.NewService(pricingRepo, distanceCalculator, clock)

	// Create routing service with OSRM. OSRM_BASE_URL can point to a self-hosted instance.
	httpClient := httpinfra.NewClient()
	routingService := routingdomain.NewOSRMRoutingService(cfg.OSRMBaseURL, httpClient)

	// Create payment transaction use case
	createTransactionUC := paymentuc.NewCreateTransactionUseCase(paymentRepo, clock, idGen)
	yooClient := httpinfra.NewYooKassaClient(cfg.YooKassaShopID, cfg.YooKassaSecret, cfg.YooKassaReturnURL, cfg.YooKassaPayoutGatewayID, cfg.YooKassaPayoutSecret, cfg.YooKassaPayoutMode)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, orderRepo, pricingService, yookassaProvider{client: yooClient}, clock, idGen, cfg.FinancePendingHoldSeconds, cfg.MinimumWithdrawalKopecks, cfg.YooKassaWebhookSecret)
	driverGates := driveruc.NewGateService(userRepo, clock, cfg.DriverSubscriptionRequired)

	matcher := matchinguc.NewFinder(orderRepo, driverRepo, matchingService, eventPublisher, clock)
	createUC := orderuc.NewCreateOrderUseCase(orderRepo, matcher, pricingService, createTransactionUC, eventPublisher, clock, idGen, appLogger)
	acceptUC := orderuc.NewAcceptOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	updateUC := orderuc.NewUpdateStatusUseCase(orderRepo, driverRepo, eventPublisher, financeUC, clock)
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	setDriverStatusUC := driveruc.NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, eventPublisher, clock, appLogger)

	orderHandler := httptransport.NewOrderHandler(createUC, acceptUC, updateUC, cancelUC, orderRepo, serviceAreaRepo, driverGates)
	// NPD service uses the stub provider until the FNS Moy Nalog partner
	// agreement is signed. Swap StubNPDProvider for a real client (e.g.
	// lknpd.nalog.ru OAuth2) when partner credentials are available.
	npdService := driveruc.NewNPDService(userRepo, driveruc.StubNPDProvider{}, clock)
	driverHandler := httptransport.NewDriverHandler(setDriverStatusUC, driverRepo, locationRepo, userRepo, verificationRepo, driverGates, npdService, clock)
	paymentHandler := httptransport.NewPaymentHandler(paymentRepo, financeUC, orderRepo, driverGates, idGen, clock)
	pricingHandler := httptransport.NewPricingHandler(pricingService)
	routingHandler := httptransport.NewRoutingHandler(routingService, orderRepo)
	serviceAreaHandler := httptransport.NewServiceAreaHandler(serviceAreaRepo)
	adminHandler := httptransport.NewAdminHandler(
		adminRepo,
		driverRepo,
		locationRepo,
		orderRepo,
		idGen,
		clock,
		httptransport.DocumentStorageConfig{
			Endpoint:      cfg.S3Endpoint,
			Region:        cfg.S3Region,
			Bucket:        cfg.S3Bucket,
			AccessKey:     cfg.S3AccessKey,
			SecretKey:     cfg.S3SecretKey,
			PublicBaseURL: cfg.S3PublicBaseURL,
		},
	)
	tokenManager := auth.NewTokenManager(cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	authHandler := httptransport.NewAuthHandler(tokenManager, userRepo, cfg.AdminUserID, cfg.AdminPassword, idGen, clock, !cfg.IsProduction())
	hub := wsinfra.NewHub()
	go hub.Run()
	wsHandler := wstransport.NewOrderWSHandler(hub, cfg.AllowedOrigins, logger, tokenManager)
	eventRelay := wsinfra.NewOrderEventRelay(hub, eventPublisher, logger)
	go eventRelay.Run(context.Background())
	scheduler := NewScheduler(financeUC, logger, cfg.BalanceReleaseInterval)

	router := httptransport.NewRouter(authHandler, orderHandler, driverHandler, paymentHandler, pricingHandler, routingHandler, adminHandler, serviceAreaHandler, wsHandler, tokenManager, cfg.AllowedOrigins, cfg.ExposeSwagger)
	return &Container{Router: router, Scheduler: scheduler, db: db, rdb: rdb}, nil
}

func EnsureSchema(db *sql.DB) error {
	const schema = `
CREATE TABLE IF NOT EXISTS users (
	id TEXT PRIMARY KEY,
	phone TEXT NOT NULL,
	full_name TEXT NOT NULL,
	role TEXT NOT NULL,
	password_hash TEXT,
	status TEXT NOT NULL DEFAULT 'active',
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_role ON users (phone, role);
CREATE INDEX IF NOT EXISTS idx_users_role_status ON users (role, status);

CREATE TABLE IF NOT EXISTS user_refresh_sessions (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	role TEXT NOT NULL,
	token_hash TEXT NOT NULL UNIQUE,
	expires_at TIMESTAMPTZ NOT NULL,
	revoked_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_user_created ON user_refresh_sessions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_active_hash ON user_refresh_sessions (token_hash) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS phone_otps (
	id TEXT PRIMARY KEY,
	phone TEXT NOT NULL,
	role TEXT NOT NULL,
	code_hash TEXT NOT NULL,
	expires_at TIMESTAMPTZ NOT NULL,
	consumed_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_phone_otps_lookup ON phone_otps (phone, role, created_at DESC);

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
	price_total NUMERIC(12,2) NOT NULL DEFAULT 0,
	payment_method TEXT NOT NULL DEFAULT 'cash',
	financial_status TEXT NOT NULL DEFAULT 'pending',
	financially_completed_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	cancelled_at TIMESTAMPTZ
);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS tow_truck_type TEXT NOT NULL DEFAULT 'standard';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS price_total NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'cash';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS financial_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS financially_completed_at TIMESTAMPTZ;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION cents_to_rub(cents BIGINT)
RETURNS NUMERIC AS $$
	SELECT ROUND((cents::NUMERIC / 100), 2);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION rub_to_cents(amount NUMERIC)
RETURNS BIGINT AS $$
	SELECT ROUND(amount * 100)::BIGINT;
$$ LANGUAGE SQL IMMUTABLE;

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
	provider TEXT NOT NULL DEFAULT 'yookassa',
	provider_payment_method_id TEXT,
	provider_payment_id TEXT,
	brand TEXT NOT NULL,
	last4 TEXT NOT NULL,
	exp_month INTEGER NOT NULL,
	exp_year INTEGER NOT NULL,
	holder TEXT NOT NULL,
	status TEXT NOT NULL DEFAULT 'active',
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'yookassa';
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider_payment_method_id TEXT;
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider_payment_id TEXT;
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
CREATE INDEX IF NOT EXISTS idx_payment_methods_user_id ON payment_methods (user_id, is_default DESC, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_methods_provider_method_id ON payment_methods (provider, provider_payment_method_id) WHERE provider_payment_method_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_methods_provider_payment_id ON payment_methods (provider_payment_id) WHERE provider_payment_id IS NOT NULL;

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

CREATE TABLE IF NOT EXISTS payments (
	id TEXT PRIMARY KEY,
	order_id TEXT,
	driver_id TEXT,
	user_id TEXT NOT NULL,
	provider TEXT NOT NULL,
	provider_payment_id TEXT,
	payment_method TEXT NOT NULL,
	purpose TEXT NOT NULL DEFAULT 'order',
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	status TEXT NOT NULL,
	confirmation_url TEXT,
	idempotency_key TEXT NOT NULL UNIQUE,
	paid_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_provider_payment_id ON payments (provider, provider_payment_id) WHERE provider_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_order_id_created_at ON payments (order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_user_id_created_at ON payments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status_created_at ON payments (status, created_at DESC);

CREATE TABLE IF NOT EXISTS driver_wallets (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL UNIQUE,
	available_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
	pending_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
	debt_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
	currency TEXT NOT NULL DEFAULT 'RUB',
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_wallets_driver_id ON driver_wallets (driver_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_wallets_driver_id_unique ON driver_wallets (driver_id);

CREATE TABLE IF NOT EXISTS wallet_transactions (
	id TEXT PRIMARY KEY,
	wallet_id TEXT NOT NULL REFERENCES driver_wallets(id),
	driver_id TEXT NOT NULL,
	order_id TEXT,
	payment_id TEXT,
	payout_id TEXT,
	type TEXT NOT NULL,
	direction TEXT NOT NULL,
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	status TEXT NOT NULL,
	description TEXT NOT NULL DEFAULT '',
	idempotency_key TEXT NOT NULL UNIQUE,
	available_after TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_driver_created_at ON wallet_transactions (driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_pending_release ON wallet_transactions (type, status, available_after) WHERE type = 'order_income' AND status = 'pending';
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_order_id ON wallet_transactions (order_id);

CREATE TABLE IF NOT EXISTS payouts (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL,
	wallet_id TEXT NOT NULL REFERENCES driver_wallets(id),
	provider TEXT NOT NULL,
	provider_payout_id TEXT,
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	status TEXT NOT NULL,
	failure_reason TEXT,
	idempotency_key TEXT NOT NULL DEFAULT '',
	paid_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE payouts ADD COLUMN IF NOT EXISTS idempotency_key TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_payouts_driver_created_at ON payouts (driver_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_provider_payout_id ON payouts (provider, provider_payout_id) WHERE provider_payout_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_idempotency_key ON payouts (idempotency_key) WHERE idempotency_key <> '';

CREATE TABLE IF NOT EXISTS driver_payout_methods (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL,
	provider_recipient_id TEXT NOT NULL,
	type TEXT NOT NULL,
	masked_value TEXT NOT NULL,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	status TEXT NOT NULL DEFAULT 'active',
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_payout_methods_driver_default ON driver_payout_methods (driver_id, is_default DESC, created_at DESC);

CREATE TABLE IF NOT EXISTS subscriptions (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL,
	plan_id TEXT NOT NULL,
	payment_id TEXT NOT NULL UNIQUE REFERENCES payments(id),
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	status TEXT NOT NULL,
	starts_at TIMESTAMPTZ,
	ends_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_driver_status ON subscriptions (driver_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS commission_rules (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	percent NUMERIC(5,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	starts_at TIMESTAMPTZ NOT NULL,
	ends_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS refunds (
	id TEXT PRIMARY KEY,
	payment_id TEXT NOT NULL REFERENCES payments(id),
	provider_refund_id TEXT,
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	reason TEXT NOT NULL,
	status TEXT NOT NULL,
	idempotency_key TEXT NOT NULL UNIQUE,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refunds_payment_id ON refunds (payment_id);

CREATE TABLE IF NOT EXISTS payment_webhooks (
	id TEXT PRIMARY KEY,
	provider TEXT NOT NULL,
	event_type TEXT NOT NULL,
	payload JSONB NOT NULL,
	processed BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL,
	processed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS finance_reports_exports (
	id TEXT PRIMARY KEY,
	report_type TEXT NOT NULL,
	status TEXT NOT NULL,
	file_url TEXT,
	requested_by TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS wallet_transaction_locks (
	idempotency_key TEXT PRIMARY KEY,
	created_at TIMESTAMPTZ NOT NULL
);

INSERT INTO commission_rules (id, name, percent, currency, is_active, starts_at, created_at)
VALUES ('tow-truck-default-commission', 'Tow Truck default marketplace commission', 15.00, 'RUB', TRUE, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET percent = EXCLUDED.percent, is_active = TRUE;

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

CREATE TABLE IF NOT EXISTS service_areas (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	min_lat DOUBLE PRECISION NOT NULL,
	min_lng DOUBLE PRECISION NOT NULL,
	max_lat DOUBLE PRECISION NOT NULL,
	max_lng DOUBLE PRECISION NOT NULL,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_service_areas_active_bounds ON service_areas (is_active, min_lat, max_lat, min_lng, max_lng);

INSERT INTO service_areas (id, name, min_lat, min_lng, max_lat, max_lng, is_active, created_at, updated_at)
VALUES ('moscow-default', 'Moscow default area', 55.20, 36.80, 56.20, 38.40, TRUE, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET is_active = EXCLUDED.is_active, updated_at = NOW();

CREATE TABLE IF NOT EXISTS driver_tax_profiles (
	driver_id TEXT PRIMARY KEY,
	inn TEXT NOT NULL,
	taxpayer_type TEXT NOT NULL,
	verification_status TEXT NOT NULL DEFAULT 'pending',
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	CONSTRAINT driver_tax_profiles_inn_format CHECK (inn ~ '^[0-9]{10}([0-9]{2})?$'),
	CONSTRAINT driver_tax_profiles_taxpayer_type CHECK (taxpayer_type IN ('self_employed', 'ip')),
	CONSTRAINT driver_tax_profiles_status CHECK (verification_status IN ('pending', 'verified', 'rejected'))
);

CREATE INDEX IF NOT EXISTS idx_driver_tax_profiles_status ON driver_tax_profiles (verification_status, updated_at DESC);

ALTER TABLE driver_tax_profiles ADD COLUMN IF NOT EXISTS npd_access_token TEXT;
ALTER TABLE driver_tax_profiles ADD COLUMN IF NOT EXISTS npd_refresh_token TEXT;
ALTER TABLE driver_tax_profiles ADD COLUMN IF NOT EXISTS npd_token_expires_at TIMESTAMPTZ;
ALTER TABLE driver_tax_profiles ADD COLUMN IF NOT EXISTS npd_connected_at TIMESTAMPTZ;
ALTER TABLE driver_tax_profiles ADD COLUMN IF NOT EXISTS npd_revoked_at TIMESTAMPTZ;
ALTER TABLE driver_tax_profiles ADD COLUMN IF NOT EXISTS npd_connection_status TEXT NOT NULL DEFAULT 'not_connected';

ALTER TABLE driver_tax_profiles DROP CONSTRAINT IF EXISTS driver_tax_profiles_npd_status;
ALTER TABLE driver_tax_profiles ADD CONSTRAINT driver_tax_profiles_npd_status
	CHECK (npd_connection_status IN ('not_connected', 'connected', 'revoked', 'error'));

CREATE INDEX IF NOT EXISTS idx_driver_tax_profiles_npd_status
	ON driver_tax_profiles (npd_connection_status, updated_at DESC);

ALTER TABLE users ADD COLUMN IF NOT EXISTS fns_full_name TEXT;
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
