package ws

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	gws "github.com/gorilla/websocket"
	"github.com/google/uuid"
)

type AuthWSHandler struct {
	hub        *EnhancedHub
	upgrader   gws.Upgrader
	logger     *log.Logger
	jwtSecret  []byte
}

type AuthPayload struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
	Phone  string `json:"phone"`
}

func NewAuthWSHandler(hub *EnhancedHub, jwtSecret string, logger *log.Logger) *AuthWSHandler {
	return &AuthWSHandler{
		hub:       hub,
		jwtSecret: []byte(jwtSecret),
		upgrader: gws.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true }, // В продакшене нужно ограничить
		},
		logger: logger,
	}
}

func (h *AuthWSHandler) Handle(w http.ResponseWriter, r *http.Request) {
	// Извлекаем JWT token из query параметра или header
	token := h.extractToken(r)
	if token == "" {
		h.logger.Printf("WS auth failed: missing token")
		http.Error(w, "Missing authentication token", http.StatusUnauthorized)
		return
	}

	// Валидируем JWT token
	authPayload, err := h.validateToken(token)
	if err != nil {
		h.logger.Printf("WS auth failed: invalid token - %v", err)
		http.Error(w, "Invalid authentication token", http.StatusUnauthorized)
		return
	}

	// Upgrade соединения
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Printf("WS upgrade failed: %v", err)
		return
	}

	// Создаем authenticated client
	client := &EnhancedClient{
		ID:     uuid.New().String(),
		UserID: authPayload.UserID,
		Role:   authPayload.Role,
		Conn:   conn,
		Send:   make(chan []byte, 64),
		Hub:    h.hub,
	}

	// Регистрируем клиента
	h.hub.Register(client)

	h.logger.Printf("WS client connected: %s (user: %s, role: %s)", client.ID, client.UserID, client.Role)

	// Отправляем приветственное сообщение
	h.sendWelcomeMessage(client)

	// Запускаем goroutines для обработки сообщений
	go h.writePump(client)
	go h.readPump(client)
}

func (h *AuthWSHandler) extractToken(r *http.Request) string {
	// Сначала проверяем query параметр
	if token := r.URL.Query().Get("token"); token != "" {
		return token
	}

	// Затем проверяем Authorization header
	authHeader := r.Header.Get("Authorization")
	if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
		return strings.TrimPrefix(authHeader, "Bearer ")
	}

	return ""
}

func (h *AuthWSHandler) validateToken(tokenString string) (*AuthPayload, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return h.jwtSecret, nil
	})

	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return nil, jwt.ErrTokenNotValidYet
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, jwt.ErrInvalidKey
	}

	return &AuthPayload{
		UserID: claims["sub"].(string),
		Role:   claims["role"].(string),
		Phone:  claims["phone"].(string),
	}, nil
}

func (h *AuthWSHandler) sendWelcomeMessage(client *EnhancedClient) {
	welcomeMsg := WSMessage{
		Type: "welcome",
		Payload: map[string]interface{}{
			"message":   "WebSocket connection established",
			"client_id": client.ID,
			"user_id":   client.UserID,
			"role":      client.Role,
		},
		Timestamp: time.Now(),
	}

	msgBytes, err := json.Marshal(welcomeMsg)
	if err != nil {
		return
	}

	select {
	case client.Send <- msgBytes:
	default:
		h.hub.Unregister(client)
	}
}

func (h *AuthWSHandler) readPump(client *EnhancedClient) {
	defer func() {
		h.hub.Unregister(client)
		client.Conn.Close()
		h.logger.Printf("WS client disconnected: %s (user: %s)", client.ID, client.UserID)
	}()

	// Настройки для keep-alive
	client.Conn.SetReadLimit(512)
	client.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	client.Conn.SetPongHandler(func(string) error {
		client.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		var msg map[string]interface{}
		err := client.Conn.ReadJSON(&msg)
		if err != nil {
			if gws.IsUnexpectedCloseError(err, gws.CloseGoingAway, gws.CloseAbnormalClosure) {
				h.logger.Printf("WS read error: %v", err)
			}
			break
		}

		// Обрабатываем входящие сообщения от клиента
		h.handleClientMessage(client, msg)
	}
}

func (h *AuthWSHandler) writePump(client *EnhancedClient) {
	ticker := time.NewTicker(54 * time.Second) // Ping interval
	defer func() {
		ticker.Stop()
		client.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-client.Send:
			client.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				client.Conn.WriteMessage(gws.CloseMessage, []byte{})
				return
			}

			if err := client.Conn.WriteMessage(gws.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			client.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := client.Conn.WriteMessage(gws.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (h *AuthWSHandler) handleClientMessage(client *EnhancedClient, msg map[string]interface{}) {
	msgType, ok := msg["type"].(string)
	if !ok {
		return
	}

	switch msgType {
	case "ping":
		// Ответ на ping
		pongMsg := WSMessage{
			Type: "pong",
			Payload: map[string]interface{}{
				"timestamp": time.Now().Format(time.RFC3339),
			},
			Timestamp: time.Now(),
		}

		msgBytes, _ := json.Marshal(pongMsg)
		select {
		case client.Send <- msgBytes:
		default:
		}

	case "driver_location":
		// Только водители могут отправлять локацию
		if client.Role == "driver" {
			h.handleDriverLocation(client, msg)
		}

	default:
		h.logger.Printf("Unknown message type: %s from client %s", msgType, client.ID)
	}
}

func (h *AuthWSHandler) handleDriverLocation(client *EnhancedClient, msg map[string]interface{}) {
	payload, ok := msg["payload"].(map[string]interface{})
	if !ok {
		return
	}

	orderID, _ := payload["order_id"].(string)
	lat, _ := payload["latitude"].(float64)
	lng, _ := payload["longitude"].(float64)
	clientID, _ := payload["client_id"].(string)

	if orderID != "" && clientID != "" {
		h.hub.BroadcastDriverLocation(orderID, client.UserID, clientID, lat, lng)
	}
}