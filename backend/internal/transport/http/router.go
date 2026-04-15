package http

import (
	nethttp "net/http"

	ws "evik/backend/internal/transport/ws"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func NewRouter(orderHandler *OrderHandler, wsHandler *ws.OrderWSHandler) nethttp.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/orders", orderHandler.CreateOrder)
	})
	r.Get("/ws/orders", wsHandler.Handle)
	return r
}
