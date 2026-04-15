package ws

import (
	"log"
	"net/http"

	wsinfra "evik/backend/internal/infrastructure/websocket"
	gws "github.com/gorilla/websocket"
)

type OrderWSHandler struct {
	hub      *wsinfra.Hub
	upgrader gws.Upgrader
	logger   *log.Logger
}

func NewOrderWSHandler(hub *wsinfra.Hub, logger *log.Logger) *OrderWSHandler {
	return &OrderWSHandler{
		hub: hub,
		upgrader: gws.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
		logger: logger,
	}
}

func (h *OrderWSHandler) Handle(w http.ResponseWriter, r *http.Request) {
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Printf("ws upgrade failed: %v", err)
		return
	}

	client := &wsinfra.Client{Conn: conn, Send: make(chan []byte, 64)}
	h.hub.Register(client)

	go h.writePump(client)
	go h.readPump(client)
}

func (h *OrderWSHandler) readPump(c *wsinfra.Client) {
	defer func() {
		h.hub.Unregister(c)
		_ = c.Conn.Close()
	}()

	for {
		if _, _, err := c.Conn.ReadMessage(); err != nil {
			return
		}
	}
}

func (h *OrderWSHandler) writePump(c *wsinfra.Client) {
	defer func() { _ = c.Conn.Close() }()
	for msg := range c.Send {
		if err := c.Conn.WriteMessage(gws.TextMessage, msg); err != nil {
			return
		}
	}
}
