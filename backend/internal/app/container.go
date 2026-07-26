package app

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/redis/go-redis/v9"

	"evik/backend/internal/auth"
	"evik/backend/internal/config"
	domainmatching "evik/backend/internal/domain/matching"
	pricingdomain "evik/backend/internal/domain/pricing"
	routingdomain "evik/backend/internal/domain/routing"
	servicearea "evik/backend/internal/domain/servicearea"
	"evik/backend/internal/infrastructure/fcm"
	"evik/backend/internal/infrastructure/geocoding"
	httpinfra "evik/backend/internal/infrastructure/http"
	"evik/backend/internal/infrastructure/postgres"
	redisinfra "evik/backend/internal/infrastructure/redis"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	httptransport "evik/backend/internal/transport/http"
	wstransport "evik/backend/internal/transport/ws"
	driveruc "evik/backend/internal/usecase/driver"
	orderuc "evik/backend/internal/usecase/order"
	paymentuc "evik/backend/internal/usecase/payment"
)

type Container struct {
	Router             http.Handler
	Scheduler          *Scheduler
	ExpansionScheduler *SearchExpansionScheduler
	DispatchScheduler  *DispatchScheduler
	DriverPresenceReaper *DriverPresenceReaper
	StuckOrderReaper     *StuckOrderReaper
	RateLimiter        *httptransport.RateLimiter
	db                 *sql.DB
	rdb                *redis.Client
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

// mapProviderError translates infrastructure transport errors into the
// usecase-level sentinels the HTTP handlers know how to status-map, keeping the
// transport layer decoupled from the YooKassa client's concrete error types.
func mapProviderError(err error) error {
	switch {
	case errors.Is(err, httpinfra.ErrCredentialsNotConfigured):
		return fmt.Errorf("%w: %v", paymentuc.ErrProviderNotConfigured, err)
	case errors.Is(err, httpinfra.ErrUpstreamUnauthorized):
		return fmt.Errorf("%w: %v", paymentuc.ErrProviderUnauthorized, err)
	case errors.Is(err, httpinfra.ErrUpstreamUnavailable):
		return fmt.Errorf("%w: %v", paymentuc.ErrProviderUnavailable, err)
	default:
		return err
	}
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
		return nil, mapProviderError(err)
	}
	return &paymentuc.ProviderPaymentResponse{ID: res.ID, Status: res.Status, ConfirmationURL: res.ConfirmationURL, Paid: res.Paid}, nil
}

func (p yookassaProvider) GetPayment(ctx context.Context, id string) (*paymentuc.ProviderPaymentResponse, error) {
	res, err := p.client.GetPayment(ctx, id)
	if err != nil {
		return nil, mapProviderError(err)
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
		return nil, mapProviderError(err)
	}
	return &paymentuc.ProviderPayoutResponse{ID: res.ID, Status: res.Status}, nil
}

// serviceAreaBBoxLookup adapts the service-area repository to fcm.AreaBBoxLookup.
type serviceAreaBBoxLookup struct{ repo servicearea.Repository }

func (s serviceAreaBBoxLookup) GetAreaBBox(ctx context.Context, cityID string) (minLat, minLng, maxLat, maxLng float64, err error) {
	area, err := s.repo.GetByID(ctx, cityID)
	if err != nil {
		return 0, 0, 0, 0, err
	}
	return area.MinLat, area.MinLng, area.MaxLat, area.MaxLng, nil
}

// cityDetectorAdapter adapts servicearea.Repository.CheckPoint to driveruc.CityDetector.
type cityDetectorAdapter struct{ repo servicearea.Repository }

func (c cityDetectorAdapter) DetectCity(ctx context.Context, lat, lng float64) (string, bool, error) {
	area, ok, err := c.repo.CheckPoint(ctx, lat, lng)
	if err != nil || !ok {
		return "", ok, err
	}
	return area.ID, true, nil
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
	paymentRepo := postgres.NewPaymentRepository(db)
	userRepo := postgres.NewUserRepository(db)
	serviceAreaRepo := postgres.NewServiceAreaRepository(db)
	pricingRepo := postgres.NewPricingRepository(db)
	adminRepo := postgres.NewAdminRepository(db)
	verificationRepo := postgres.NewDriverVerificationRepository(db)
	locationRepo := redisinfra.NewLocationStore(rdb)
	driverRepo := postgres.NewDriverRepository(db, locationRepo)
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

	// Platform settings repository (used by payment, admin, etc.)
	settingsRepo := postgres.NewSettingsRepository(db)

	offerRepo := postgres.NewOfferRepository(db)

	// Create payment use cases
	yooClient := httpinfra.NewYooKassaClient(cfg.YooKassaShopID, cfg.YooKassaSecret, cfg.YooKassaReturnURL, cfg.YooKassaPayoutGatewayID, cfg.YooKassaPayoutSecret, cfg.YooKassaPayoutMode)
	financeUC := paymentuc.NewFinanceUseCase(paymentRepo, orderRepo, driverRepo, pricingService, yookassaProvider{client: yooClient}, settingsRepo, clock, idGen, cfg.FinancePendingHoldSeconds, cfg.MinimumWithdrawalKopecks, eventPublisher)
	driverGates := driveruc.NewGateService(userRepo, clock, cfg.DriverSubscriptionRequired, cfg.DriverGateBypass, cfg.DebugMode)

	// FCM push sender. Falls back to a silent no-op when FIREBASE_CREDENTIALS_JSON
	// is empty so local/dev without Firebase credentials still boot cleanly.
	var pushSender orderuc.PushSender
	if cfg.FirebaseCredentialsJSON == "" {
		pushSender = fcm.NewNoop()
		logger.Printf("INFO: FIREBASE_CREDENTIALS_JSON not set — using noop FCM sender")
	} else {
		realSender, err := fcm.New(context.Background(), []byte(cfg.FirebaseCredentialsJSON), userRepo, serviceAreaBBoxLookup{serviceAreaRepo}, locationRepo, appLogger)
		if err != nil {
			logger.Printf("WARN: failed to init FCM sender, falling back to noop: %v", err)
			pushSender = fcm.NewNoop()
		} else {
			pushSender = realSender
			logger.Printf("INFO: firebase push sender initialized")
		}
	}

	createUC := orderuc.NewCreateOrderUseCase(orderRepo, pricingService, eventPublisher, clock, idGen, appLogger)
	acceptUC := orderuc.NewAcceptOrderUseCase(db, orderRepo, driverRepo, offerRepo, locationRepo, locationRepo, serviceAreaRepo, eventPublisher, pushSender, clock, appLogger)
	updateUC := orderuc.NewUpdateStatusUseCase(orderRepo, driverRepo, eventPublisher, pushSender, clock, appLogger)
	cancelUC := orderuc.NewCancelOrderUseCase(orderRepo, driverRepo, eventPublisher, clock, appLogger)
	finalizeUC := orderuc.NewFinalizeOrderUseCase(orderRepo, eventPublisher, pushSender, clock, appLogger)
	setDriverStatusUC := driveruc.NewSetStatusUseCase(driverRepo, orderRepo, locationRepo, eventPublisher, cityDetectorAdapter{serviceAreaRepo}, locationRepo, clock, appLogger)

	allowMockLocation := cfg.AllowMockLocation
	isProduction := cfg.IsProduction()
	orderHandler := httptransport.NewOrderHandler(createUC, acceptUC, updateUC, cancelUC, finalizeUC, orderRepo, serviceAreaRepo, driverGates, locationRepo, locationRepo, cfg.OrderExpansionRadiusKM, cfg.DriverLastCityTTL, allowMockLocation, isProduction)
	// NPD service uses the stub provider until the FNS Moy Nalog partner
	// agreement is signed. Swap StubNPDProvider for a real client (e.g.
	// lknpd.nalog.ru OAuth2) when partner credentials are available.
	npdService := driveruc.NewNPDService(userRepo, driveruc.StubNPDProvider{}, clock)
	driverHandler := httptransport.NewDriverHandler(setDriverStatusUC, driverRepo, locationRepo, userRepo, verificationRepo, orderRepo, driverGates, npdService, clock, allowMockLocation, isProduction, cfg.DebugMode)
	yooKassaVerifier := paymentuc.NewYooKassaVerifier()
	paymentHandler := httptransport.NewPaymentHandler(paymentRepo, financeUC, orderRepo, driverGates, idGen, clock, yooKassaVerifier)
	pricingHandler := httptransport.NewPricingHandler(pricingService)
	routingHandler := httptransport.NewRoutingHandler(routingService, orderRepo)
	serviceAreaHandler := httptransport.NewServiceAreaHandler(serviceAreaRepo)
	cityGeocoder := geocoding.NewNominatim()
	cityHandler := httptransport.NewCityHandler(serviceAreaRepo, cityGeocoder, idGen)
	driverLocationsHandler := httptransport.NewDriverLocationsHandler(driverRepo, locationRepo, serviceAreaRepo)
	offerHandler := httptransport.NewOfferHandler(offerRepo, orderRepo)
	settingsHandler := httptransport.NewSettingsHandler(settingsRepo)
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
	authHandler := httptransport.NewAuthHandler(tokenManager, userRepo, cfg.AdminUserID, cfg.AdminPassword, idGen, clock, !cfg.IsProduction(), cfg.OTPFixedCode, cfg.IsProduction(), cfg.DebugMode)
	hub := wsinfra.NewHub()
	go hub.Run()
	wsHandler := wstransport.NewOrderWSHandler(hub, cfg.AllowedOrigins, logger, tokenManager, locationRepo, orderRepo, eventPublisher, clock.Now)
	eventRelay := wsinfra.NewOrderEventRelay(hub, eventPublisher, locationRepo, logger)
	go eventRelay.Run(context.Background())
	scheduler := NewScheduler(financeUC, paymentRepo, logger, cfg.BalanceReleaseInterval)
	expansionScheduler := NewSearchExpansionScheduler(
		orderRepo,
		locationRepo,
		pushSender,
		eventPublisher,
		logger,
		cfg.OrderExpansionCheckInterval,
		cfg.OrderExpansionDelay,
		cfg.OrderExpansionRadiusKM,
		cfg.DriverLastCityTTL,
	)

	dispatchScheduler := NewDispatchScheduler(
		offerRepo,
		orderRepo,
		matchingService,
		settingsRepo,
		hub,
		eventPublisher,
		pushSender,
		idGen,
		clock,
		logger,
		cfg.DispatchCheckInterval,
		cfg.DispatchOfferTimeout,
		cfg.DispatchGeoFreshness,
	)

	driverPresenceReaper := NewDriverPresenceReaper(
		driverRepo,
		locationRepo,
		hub,
		eventPublisher,
		logger,
		cfg.DriverPresenceReaperInterval,
		cfg.DriverPresenceGracePeriod,
	)

	stuckOrderReaper := NewStuckOrderReaper(
		db,
		orderRepo,
		driverRepo,
		eventPublisher,
		logger,
		cfg.StuckOrderReaperInterval,
		cfg.StuckSearchingTimeout,
		cfg.StuckAcceptedTimeout,
		cfg.StuckArrivedFlagThreshold,
		cfg.StuckInProgressFlagThreshold,
		cfg.StuckAwaitingPaymentFlagThreshold,
		cfg.StuckAcceptedAction,
	)

	limiter := httptransport.NewRateLimiter()
	router := httptransport.NewRouter(authHandler, orderHandler, offerHandler, driverHandler, paymentHandler, pricingHandler, routingHandler, adminHandler, settingsHandler, serviceAreaHandler, cityHandler, driverLocationsHandler, wsHandler, tokenManager, cfg.AllowedOrigins, cfg.ExposeSwagger, limiter, cfg.DebugMode)
	return &Container{Router: router, Scheduler: scheduler, ExpansionScheduler: expansionScheduler, DispatchScheduler: dispatchScheduler, DriverPresenceReaper: driverPresenceReaper, StuckOrderReaper: stuckOrderReaper, RateLimiter: limiter, db: db, rdb: rdb}, nil
}

func (c *Container) Close() {
	if c.db != nil {
		_ = c.db.Close()
	}
	if c.rdb != nil {
		_ = c.rdb.Close()
	}
}
