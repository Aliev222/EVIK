package ws

import (
	"encoding/json"
	"sync"
	"time"

	gws "github.com/gorilla/websocket"
)

// Enhanced Client with user context
type EnhancedClient struct {
	ID     string
	UserID string
	Role   string // "client", "driver", "admin"
	Conn   *gws.Conn
	Send   chan []byte
	Hub    *EnhancedHub
}

// Enhanced Hub with user-specific messaging
type EnhancedHub struct {
	// Map userID -> client for direct messaging
	userClients map[string]*EnhancedClient
	// All clients map
	clients    map[*EnhancedClient]struct{}
	register   chan *EnhancedClient
	unregister chan *EnhancedClient
	broadcast  chan []byte
	// User-specific message
	userMessage chan *UserMessage
	mu          sync.RWMutex
}

type UserMessage struct {
	UserID  string
	Message []byte
}

// WebSocket message types
type WSMessage struct {
	Type      string      `json:"type"`
	Payload   interface{} `json:"payload"`
	Timestamp time.Time   `json:"timestamp"`
}

// Order-related message types
type OrderEventMessage struct {
	OrderID    string `json:"order_id"`
	Status     string `json:"status"`
	ClientID   string `json:"client_id,omitempty"`
	DriverID   string `json:"driver_id,omitempty"`
	Message    string `json:"message"`
	UpdatedAt  string `json:"updated_at"`
}

type DriverLocationMessage struct {
	OrderID   string  `json:"order_id"`
	DriverID  string  `json:"driver_id"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	UpdatedAt string  `json:"updated_at"`
}

func NewEnhancedHub() *EnhancedHub {
	return &EnhancedHub{
		userClients: make(map[string]*EnhancedClient),
		clients:     make(map[*EnhancedClient]struct{}),
		register:    make(chan *EnhancedClient),
		unregister:  make(chan *EnhancedClient),
		broadcast:   make(chan []byte, 128),
		userMessage: make(chan *UserMessage, 128),
	}
}

func (h *EnhancedHub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = struct{}{}
			h.userClients[client.UserID] = client
			h.mu.Unlock()

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				delete(h.userClients, client.UserID)
				close(client.Send)
			}
			h.mu.Unlock()

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.Send <- message:
				default:
					// Client buffer full, disconnect
					delete(h.clients, client)
					delete(h.userClients, client.UserID)
					close(client.Send)
				}
			}
			h.mu.RUnlock()

		case userMsg := <-h.userMessage:
			h.mu.RLock()
			if client, exists := h.userClients[userMsg.UserID]; exists {
				select {
				case client.Send <- userMsg.Message:
				default:
					// Client buffer full, disconnect
					delete(h.clients, client)
					delete(h.userClients, client.UserID)
					close(client.Send)
				}
			}
			h.mu.RUnlock()
		}
	}
}

func (h *EnhancedHub) Register(client *EnhancedClient) {
	h.register <- client
}

func (h *EnhancedHub) Unregister(client *EnhancedClient) {
	h.unregister <- client
}

func (h *EnhancedHub) Broadcast(message []byte) {
	h.broadcast <- message
}

func (h *EnhancedHub) SendToUser(userID string, message []byte) {
	h.userMessage <- &UserMessage{
		UserID:  userID,
		Message: message,
	}
}

// Send order status update to specific users
func (h *EnhancedHub) BroadcastOrderUpdate(orderID, status, clientID, driverID string) {
	event := OrderEventMessage{
		OrderID:   orderID,
		Status:    status,
		ClientID:  clientID,
		DriverID:  driverID,
		Message:   h.getStatusMessage(status),
		UpdatedAt: time.Now().Format(time.RFC3339),
	}

	wsMsg := WSMessage{
		Type:      "order_status_update",
		Payload:   event,
		Timestamp: time.Now(),
	}

	msgBytes, err := json.Marshal(wsMsg)
	if err != nil {
		return
	}

	// Send to client
	if clientID != "" {
		h.SendToUser(clientID, msgBytes)
	}

	// Send to driver
	if driverID != "" {
		h.SendToUser(driverID, msgBytes)
	}
}

// Send driver location update to client
func (h *EnhancedHub) BroadcastDriverLocation(orderID, driverID, clientID string, lat, lng float64) {
	event := DriverLocationMessage{
		OrderID:   orderID,
		DriverID:  driverID,
		Latitude:  lat,
		Longitude: lng,
		UpdatedAt: time.Now().Format(time.RFC3339),
	}

	wsMsg := WSMessage{
		Type:      "driver_location_update",
		Payload:   event,
		Timestamp: time.Now(),
	}

	msgBytes, err := json.Marshal(wsMsg)
	if err != nil {
		return
	}

	// Send only to client
	if clientID != "" {
		h.SendToUser(clientID, msgBytes)
	}
}

// Get user-friendly status messages
func (h *EnhancedHub) getStatusMessage(status string) string {
	messages := map[string]string{
		"searching":   "Ищем водителя...",
		"accepted":    "Водитель принял заказ",
		"arrived":     "Водитель приехал",
		"in_progress": "Эвакуация в процессе",
		"completed":   "Заказ завершен",
		"cancelled":   "Заказ отменен",
	}

	if msg, exists := messages[status]; exists {
		return msg
	}
	return "Статус заказа изменен"
}

// Get connected users count for monitoring
func (h *EnhancedHub) GetStats() map[string]int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	stats := map[string]int{
		"total_clients": len(h.clients),
		"total_users":   len(h.userClients),
	}

	return stats
}