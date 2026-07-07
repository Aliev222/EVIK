package http

import (
	nethttp "net/http"

	"evik/backend/internal/auth"
	ws "evik/backend/internal/transport/ws"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	httpSwagger "github.com/swaggo/http-swagger/v2"
)

func NewRouter(
	authHandler *AuthHandler,
	orderHandler *OrderHandler,
	driverHandler *DriverHandler,
	paymentHandler *PaymentHandler,
	pricingHandler *PricingHandler,
	routingHandler *RoutingHandler,
	adminHandler *AdminHandler,
	settingsHandler *SettingsHandler,
	serviceAreaHandler *ServiceAreaHandler,
	cityHandler *CityHandler,
	driverLocationsHandler *DriverLocationsHandler,
	wsHandler *ws.OrderWSHandler,
	tokens *auth.TokenManager,
	allowedOrigins []string,
	exposeSwagger bool,
	limiter *RateLimiter,
) nethttp.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	authMW := AuthMiddleware(tokens)

	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/register", authHandler.Register)
		api.With(RateLimitByIP(limiter, 10)).Post("/auth/login", authHandler.Login)
		api.With(RateLimitByPhone(limiter, 3)).Post("/auth/otp/request", authHandler.RequestOTP)
		api.With(RateLimitByPhone(limiter, 5)).Post("/auth/otp/verify", authHandler.VerifyOTP)
		api.With(RateLimitByIP(limiter, 5)).Post("/auth/admin/login", authHandler.AdminLogin)
		api.Post("/auth/refresh", authHandler.Refresh)
		api.Post("/webhooks/yookassa", paymentHandler.HandleYooKassaWebhook)
		api.Get("/service-areas/check", serviceAreaHandler.Check)

		api.Group(func(secured chi.Router) {
			secured.Use(authMW)
			secured.Get("/auth/me", authHandler.Me)
			secured.Post("/devices/fcm-token", authHandler.UpsertDeviceToken)
			secured.Post("/devices/fcm-token/revoke", authHandler.RevokeDeviceToken)

			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/orders", orderHandler.CreateOrder)
			secured.Get("/orders", orderHandler.ListOrders)
			secured.Get("/orders/active", orderHandler.GetActiveOrder)
			secured.Get("/orders/{orderID}", orderHandler.GetOrder)
			secured.Get("/orders/{orderID}/review", adminHandler.GetOrderReview)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/orders/{orderID}/payments", paymentHandler.CreateOrderPayment)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Get("/orders/{orderID}/payment-status", paymentHandler.GetOrderPaymentStatus)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Get("/orders/{orderID}/receipt", paymentHandler.GetOrderReceipt)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/orders/{orderID}/accept", orderHandler.AcceptOrder)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/orders/{orderID}/status", orderHandler.UpdateOrderStatus)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/orders/{orderID}/finalize", orderHandler.FinalizeOrder)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/orders/{orderID}/confirm-payment", paymentHandler.ConfirmPayment)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Patch("/orders/{orderID}/payment-method", paymentHandler.UpdateOrderPaymentMethod)
			secured.Post("/orders/{orderID}/cancel", orderHandler.CancelOrder)
			secured.Get("/drivers/{driverID}", driverHandler.GetDriver)
			secured.Get("/drivers/{driverID}/profile", driverHandler.GetDriverProfile)
			secured.Get("/drivers/{driverID}/location", driverHandler.GetLocation)
			secured.Get("/drivers/{driverID}/reviews", adminHandler.GetDriverReviews)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/drivers/{driverID}/status", driverHandler.SetStatus)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/drivers/{driverID}/tax-profile", driverHandler.GetTaxProfile)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Put("/drivers/{driverID}/tax-profile", driverHandler.UpsertTaxProfile)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/drivers/{driverID}/npd/status", driverHandler.GetNPDStatus)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/drivers/{driverID}/npd/connect", driverHandler.ConnectNPD)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/drivers/{driverID}/npd/disconnect", driverHandler.DisconnectNPD)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/drivers/{driverID}/verification-status", driverHandler.GetVerificationStatus)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver-verifications", adminHandler.SubmitDriverVerification)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver-documents/uploads", adminHandler.CreateDocumentUpload)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Get("/payments/wallet", paymentHandler.GetWallet)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/client/payment-methods/init", paymentHandler.InitClientPaymentMethod)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/payments/cards", paymentHandler.AddCard)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Delete("/payments/cards/{cardID}", paymentHandler.DeleteCard)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/payments/cards/{cardID}/default", paymentHandler.SetDefaultCard)
			secured.With(RequireRoles(auth.RoleClient, auth.RoleAdmin)).Post("/payments/promocode/apply", paymentHandler.ApplyPromocode)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/driver/wallet", paymentHandler.GetDriverWallet)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/driver/wallet/transactions", paymentHandler.ListDriverWalletTransactions)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/driver/payouts", paymentHandler.ListDriverPayouts)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver/payouts/request", paymentHandler.RequestDriverPayout)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/driver/payout-methods", paymentHandler.ListDriverPayoutMethods)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver/payout-methods", paymentHandler.AddDriverPayoutMethod)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Post("/driver/subscription/payment", paymentHandler.CreateDriverSubscriptionPayment)
			secured.With(RequireRoles(auth.RoleDriver, auth.RoleAdmin)).Get("/driver/subscription/status", paymentHandler.GetDriverSubscriptionStatus)
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
				admin.Post("/reviews/{reviewID}/hide", adminHandler.HideReview)
				admin.Post("/reviews/{reviewID}/show", adminHandler.ShowReview)
				admin.Delete("/reviews/{reviewID}", adminHandler.DeleteReview)
				admin.Get("/drivers-online", adminHandler.ListOnlineDrivers)
				admin.Post("/moderation/driver-verifications/{verificationID}/approve", adminHandler.ApproveDriverVerification)
				admin.Post("/moderation/driver-verifications/{verificationID}/reject", adminHandler.RejectDriverVerification)
				admin.Post("/moderation/driver-verifications/{verificationID}/request-changes", adminHandler.RequestDriverVerificationChanges)
				admin.Post("/moderation/driver-verifications/{verificationID}/block", adminHandler.BlockDriverVerification)
				admin.Post("/moderation/batch/approve", adminHandler.BatchApproveVerifications)
				admin.Post("/moderation/batch/reject", adminHandler.BatchRejectVerifications)
				admin.Get("/orders", adminHandler.ListAdminOrders)
				admin.Get("/orders/{orderID}", adminHandler.GetAdminOrderDetails)
				admin.Get("/finance/refunds", paymentHandler.AdminListRefunds)
				// AdminFinanceReport handles every other report kind via {reportType}
				// parameter — orders / payments / payouts / wallets / transactions /
				// subscriptions / cash-debts / commissions. See
				// payment_repository.go:ExportFinanceReport for the supported set.
				admin.Get("/finance/{reportType}", paymentHandler.AdminFinanceReport)
				admin.Post("/finance/refunds", paymentHandler.AdminCreateRefund)
				admin.Post("/finance/payouts/{payoutID}/approve", paymentHandler.AdminApprovePayout)
				admin.Post("/finance/payouts/{payoutID}/reject", paymentHandler.AdminRejectPayout)
				admin.Post("/finance/export", paymentHandler.AdminExportFinance)
				admin.Get("/tax-profiles", adminHandler.ListTaxProfiles)
				admin.Post("/tax-profiles/{driverID}/verify", adminHandler.VerifyTaxProfile)
				admin.Post("/tax-profiles/{driverID}/reject", adminHandler.RejectTaxProfile)
				admin.Post("/tax-profiles/{driverID}/request-changes", adminHandler.RequestTaxProfileChanges)

				// City (service area) management.
				admin.Get("/cities/autocomplete", cityHandler.Autocomplete)
				admin.Post("/cities/search", cityHandler.Search)
				admin.Post("/cities", cityHandler.Create)
				admin.Get("/cities", cityHandler.List)
				admin.Patch("/cities/{id}", cityHandler.Patch)
				admin.Delete("/cities/{id}", cityHandler.Delete)

				// Live driver map.
				admin.Get("/drivers/locations", driverLocationsHandler.List)
				admin.Get("/drivers/{driverID}", adminHandler.GetDriverDetail)
				admin.Get("/drivers/{driverID}/orders", adminHandler.ListDriverOrders)
				admin.Get("/finance-v2/payments", adminHandler.ListAdminPayments)
				admin.Get("/finance-v2/wallets", adminHandler.ListAdminWallets)
				admin.Get("/finance-v2/transactions", adminHandler.ListAdminTransactions)
				admin.Get("/finance-v2/subscriptions", adminHandler.ListAdminSubscriptions)

				// Platform settings.
				admin.Get("/settings", settingsHandler.List)
				admin.Put("/settings", settingsHandler.Update)
				admin.Get("/audit-log", adminHandler.ListAuditLog)
			})
		})
	})
	if exposeSwagger {
		r.Get("/swagger/*", httpSwagger.WrapHandler)
	}
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
