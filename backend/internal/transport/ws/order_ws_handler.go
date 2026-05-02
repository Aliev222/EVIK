package ws

import (
	"log"
	"net/http"
	"slices"
	"strings"

	"evik/backend/internal/auth"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	gws "github.com/gorilla/websocket"
)

type OrderWSHandler struct {
	hub            *wsinfra.Hub
	upgrader       gws.Upgrader
	logger         *log.Logger
	allowedOrigins []string
	tokenManager   *auth.TokenManager
}

func NewOrderWSHandler(hub *wsinfra.Hub, allowedOrigins []string, logger *log.Logger, tokenManager *auth.TokenManager) *OrderWSHandler {
	return &OrderWSHandler{
		hub:            hub,
		allowedOrigins: allowedOrigins,
		tokenManager:   tokenManager,
		upgrader: gws.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				origin := r.Header.Get("Origin")
				// Allow requests with no Origin header (direct connections, mobile apps)
				if origin == "" {
					return true
				}
				return slices.Contains(allowedOrigins, origin)
			},
		},
		logger: logger,
	}
}

func (h *OrderWSHandler) Handle(w http.ResponseWriter, r *http.Request) {
	// Extract token from Authorization header or query parameter
	var token string
	authHeader := r.Header.Get("Authorization")
	if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
		token = strings.TrimPrefix(authHeader, "Bearer ")
	} else {
		// Fallback to query parameter for frontend compatibility
		token = r.URL.Query().Get("access_token")
		if token == "" {
			token = r.URL.Query().Get("token") // legacy fallback
		}
	}

	if token == "" {
		http.Error(w, "Missing authentication token", http.StatusUnauthorized)
		return
	}

	// Parse token and extract user info
	claims, err := h.tokenManager.ParseAccessToken(token)
	if err != nil {
		h.logger.Printf("ws auth failed: %v", err)
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Printf("ws upgrade failed: %v", err)
		return
	}

	client := &wsinfra.Client{
		Conn:   conn,
		Send:   make(chan []byte, 64),
		UserID: claims.UserID,
		Role:   string(claims.Role),
	}
	h.hub.Register(client)

	h.logger.Printf("WebSocket client connected: user_id=%s role=%s", claims.UserID, claims.Role)

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
