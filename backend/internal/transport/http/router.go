package http

import (
	nethttp "net/http"

	"evik/backend/internal/auth"
	ws "evik/backend/internal/transport/ws"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
)

func NewRouter(
	authHandler *AuthHandler,
	orderHandler *OrderHandler,
	driverHandler *DriverHandler,
	paymentHandler *PaymentHandler,
	pricingHandler *PricingHandler,
	routingHandler *RoutingHandler,
	adminHandler *AdminHandler,
	wsHandler *ws.OrderWSHandler,
	tokens *auth.TokenManager,
	allowedOrigins []string,
) nethttp.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	authMW := AuthMiddleware(tokens)

	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/login", authHandler.Login)
		api.Post("/auth/admin/login", authHandler.AdminLogin)
		api.Post("/auth/refresh", authHandler.Refresh)

		api.Group(func(secured chi.Router) {
			secured.Use(authMW)
			secured.Get("/auth/me", authHandler.Me)

			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/orders", orderHandler.CreateOrder)
			secured.Get("/orders", orderHandler.ListOrders)
			secured.Get("/orders/{orderID}", orderHandler.GetOrder)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/orders/{orderID}/accept", orderHandler.AcceptOrder)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/orders/{orderID}/status", orderHandler.UpdateOrderStatus)
			secured.Post("/orders/{orderID}/cancel", orderHandler.CancelOrder)
			secured.Get("/drivers/{driverID}", driverHandler.GetDriver)
			secured.Get("/drivers/{driverID}/location", driverHandler.GetLocation)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/drivers/{driverID}/status", driverHandler.SetStatus)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver-verifications", adminHandler.SubmitDriverVerification)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver-documents/uploads", adminHandler.CreateDocumentUpload)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Get("/payments/wallet", paymentHandler.GetWallet)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/payments/cards", paymentHandler.AddCard)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Delete("/payments/cards/{cardID}", paymentHandler.DeleteCard)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/payments/cards/{cardID}/default", paymentHandler.SetDefaultCard)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/payments/promocode/apply", paymentHandler.ApplyPromocode)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/reviews", adminHandler.CreateReview)

			// Pricing endpoints
			secured.Post("/pricing/calculate", pricingHandler.CalculatePrice)
			secured.Get("/pricing/tariffs", pricingHandler.GetTariffs)
			secured.Get("/pricing/tariffs/{type}", pricingHandler.GetTariffByType)

			// Routing endpoints for drivers
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/routing/orders/{orderID}/route", routingHandler.CalculateRoute)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/routing/orders/{orderID}/directions", routingHandler.GetDirections)

			secured.Route("/admin", func(admin chi.Router) {
				admin.Use(RequireRoles(auth.RoleAdmin))
				admin.Get("/overview", adminHandler.Overview)
				admin.Get("/driver-verifications", adminHandler.ListDriverVerifications)
				admin.Get("/users", adminHandler.ListUsers)
				admin.Get("/reviews", adminHandler.ListReviews)
				admin.Get("/drivers-online", adminHandler.ListOnlineDrivers)
				admin.Post("/moderation/driver-verifications/{verificationID}/approve", adminHandler.ApproveDriverVerification)
				admin.Post("/moderation/driver-verifications/{verificationID}/reject", adminHandler.RejectDriverVerification)
				admin.Post("/moderation/driver-verifications/{verificationID}/request-changes", adminHandler.RequestDriverVerificationChanges)
				admin.Post("/moderation/driver-verifications/{verificationID}/block", adminHandler.BlockDriverVerification)
			})
		})
	})
	r.Get("/healthz", func(w nethttp.ResponseWriter, r *nethttp.Request) {
		w.WriteHeader(nethttp.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	r.With(authMW).MethodFunc(nethttp.MethodHead, "/ws/orders", func(w nethttp.ResponseWriter, r *nethttp.Request) {
		w.WriteHeader(nethttp.StatusUpgradeRequired)
	})
	r.With(authMW).Get("/ws/orders", wsHandler.Handle)
	return r
}
