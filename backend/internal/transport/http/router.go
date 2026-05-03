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
	wsHandler *ws.OrderWSHandler,
	tokens *auth.TokenManager,
) nethttp.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"http://localhost:*", "http://127.0.0.1:*", "http://10.0.2.2:*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	authMW := AuthMiddleware(tokens)

	r.Route("/api/v1", func(api chi.Router) {
		// SMS Auth endpoints (новые)
		api.Post("/auth/send-sms", authHandler.SendSMS)
		api.Post("/auth/verify-sms", authHandler.VerifySMS)

		// Существующие auth endpoints
		api.Post("/auth/login", authHandler.Login)
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
