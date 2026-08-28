package ws

import (
	"context"
	"encoding/json"
	"log"
	"math"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"

	"evik/backend/internal/auth"
	"evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	gws "github.com/gorilla/websocket"
)

const (
	pongWait   = 90 * time.Second
	pingPeriod = 75 * time.Second
	writeWait  = 10 * time.Second
)

type WSLocationRepo interface {
	SaveLocation(ctx context.Context, driverID string, loc location.Location) error
}

type WSOrderRepo interface {
	GetByID(ctx context.Context, id string) (*orderdomain.Order, error)
}

type WSEventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type OrderWSHandler struct {
	hub            *wsinfra.Hub
	upgrader       gws.Upgrader
	logger         *log.Logger
	allowedOrigins []string
	tokenManager   *auth.TokenManager
	locationRepo   WSLocationRepo
	orderRepo      WSOrderRepo
	eventPublisher WSEventPublisher
	clock          func() time.Time

	lastLocationPublish   map[string]time.Time
	lastLocationPublishMu sync.Mutex

	// Distance-based throttle: skip Redis writes when driver moved < minDistanceMeters
	lastLocation    map[string][2]float64 // driverID -> [lat, lng]
	lastLocationMu  sync.Mutex
	minDistanceMeters float64
}

func NewOrderWSHandler(
	hub *wsinfra.Hub,
	allowedOrigins []string,
	logger *log.Logger,
	tokenManager *auth.TokenManager,
	locationRepo WSLocationRepo,
	orderRepo WSOrderRepo,
	eventPublisher WSEventPublisher,
	clock func() time.Time,
) *OrderWSHandler {
	return &OrderWSHandler{
		hub:            hub,
		allowedOrigins: allowedOrigins,
		tokenManager:   tokenManager,
		upgrader: gws.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
			origin := r.Header.Get("Origin")
			if origin == "" {
				return true
			}
			return slices.Contains(allowedOrigins, origin)
		},
		},
		logger:                logger,
		locationRepo:          locationRepo,
		orderRepo:             orderRepo,
		eventPublisher:        eventPublisher,
		clock:                 clock,
		lastLocationPublish:   make(map[string]time.Time),
		lastLocationPublishMu: sync.Mutex{},
		lastLocation:          make(map[string][2]float64),
		lastLocationMu:        sync.Mutex{},
		minDistanceMeters:     50, // skip Redis write if driver moved <50m
	}
}

func (h *OrderWSHandler) Handle(w http.ResponseWriter, r *http.Request) {
	var token string
	authHeader := r.Header.Get("Authorization")
	if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
		token = strings.TrimPrefix(authHeader, "Bearer ")
	} else {
		token = r.URL.Query().Get("access_token")
		if token == "" {
			token = r.URL.Query().Get("token")
		}
	}

	if token == "" {
		http.Error(w, "Missing authentication token", http.StatusUnauthorized)
		return
	}

	claims, err := h.tokenManager.ParseAccessToken(token)
	if err != nil {
		h.logger.Printf("ws auth failed: %v", err)
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Printf("ws upgrade failed (origin=%s): %v", r.Header.Get("Origin"), err)
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

type wsIncomingMessage struct {
	Type      string          `json:"type"`
	DriverID  string          `json:"driver_id,omitempty"`
	Data      json.RawMessage `json:"data,omitempty"`
	Timestamp string          `json:"timestamp,omitempty"`
}

type wsLocationData struct {
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
	Bearing float64 `json:"bearing,omitempty"`
	Speed   float64 `json:"speed,omitempty"`
	Status  string  `json:"status,omitempty"`
	OrderID string  `json:"order_id,omitempty"`
	IsMock  bool    `json:"is_mock"`
}

func (h *OrderWSHandler) readPump(c *wsinfra.Client) {
	defer func() {
		h.hub.Unregister(c)
		_ = c.Conn.Close()
	}()

	_ = c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error {
		return c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		_, msgBytes, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		_ = c.Conn.SetReadDeadline(time.Now().Add(pongWait))
		h.handleWSMessage(c, msgBytes)
	}
}

func (h *OrderWSHandler) handleWSMessage(c *wsinfra.Client, msgBytes []byte) {
	var msg wsIncomingMessage
	if err := json.Unmarshal(msgBytes, &msg); err != nil {
		h.logger.Printf("ws: failed to parse message from user=%s: %v", c.UserID, err)
		return
	}

	switch msg.Type {
	case "ping", "pong", "heartbeat":
		h.sendPong(c)
	case "location_update":
		h.handleLocationUpdate(c, msgBytes)
	case "register_driver", "register_client", "register_admin", "client_location_update", "create_order":
	default:
	}
}

// haversineMeters returns the great-circle distance in meters between two points.
func haversineMeters(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371000.0 // Earth radius in meters
	dLat := (lat2 - lat1) * math.Pi / 180
	dLng := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLng/2)*math.Sin(dLng/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

func (h *OrderWSHandler) handleLocationUpdate(c *wsinfra.Client, msgBytes []byte) {
	if c.Role != "driver" {
		return
	}

	var incoming struct {
		DriverID string          `json:"driver_id"`
		Data     json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(msgBytes, &incoming); err != nil {
		return
	}

	var locData wsLocationData
	if err := json.Unmarshal(incoming.Data, &locData); err != nil {
		h.logger.Printf("ws: failed to parse location data from driver=%s: %v", c.UserID, err)
		return
	}

	if locData.Lat < -90 || locData.Lat > 90 || locData.Lng < -180 || locData.Lng > 180 {
		h.logger.Printf("ws: invalid lat/lng from driver=%s: %f %f", c.UserID, locData.Lat, locData.Lng)
		return
	}

	h.lastLocationPublishMu.Lock()
	lastPub := h.lastLocationPublish[c.UserID]
	now := h.clock()
	if now.Sub(lastPub) < 2*time.Second {
		h.lastLocationPublishMu.Unlock()
		return
	}
	h.lastLocationPublish[c.UserID] = now
	h.lastLocationPublishMu.Unlock()

	// Distance-based throttle: skip Redis write if driver moved <50m
	// AND last update was <30s ago. This keeps geo-fresh for stationary
	// drivers while reducing Redis writes for the common case.
	h.lastLocationMu.Lock()
	prev, hasPrev := h.lastLocation[c.UserID]
	if hasPrev {
		dist := haversineMeters(prev[0], prev[1], locData.Lat, locData.Lng)
		lastWrite := h.lastLocationPublish[c.UserID]
		if dist < h.minDistanceMeters && now.Sub(lastWrite) < 30*time.Second {
			h.lastLocationMu.Unlock()
			return
		}
	}
	h.lastLocation[c.UserID] = [2]float64{locData.Lat, locData.Lng}
	h.lastLocationMu.Unlock()

	if h.locationRepo == nil {
		return
	}
	if err := h.locationRepo.SaveLocation(context.Background(), c.UserID, location.Location{
		Lat:       locData.Lat,
		Lng:       locData.Lng,
		UpdatedAt: now,
	}); err != nil {
		h.logger.Printf("ws: SaveLocation error for driver=%s: %v", c.UserID, err)
		return
	}

	if locData.OrderID != "" && h.orderRepo != nil && h.eventPublisher != nil {
		ord, ordErr := h.orderRepo.GetByID(context.Background(), locData.OrderID)
		// Only notify the client of an order this driver is actually assigned
		// to. This keeps a driver from pushing their location to bystanders.
		if ordErr == nil && ord != nil && ord.UserID != "" && ord.DriverID != nil && *ord.DriverID == c.UserID {
			payload := map[string]any{
				"driver_id": c.UserID,
				"user_id":   ord.UserID,
				"lat":       locData.Lat,
				"lng":       locData.Lng,
				"bearing":   locData.Bearing,
				"speed":     locData.Speed,
				"status":    locData.Status,
			}
			_ = h.eventPublisher.Publish(context.Background(), orderdomain.Event{
				Type:    orderdomain.EventDriverLocationUpdated,
				OrderID: locData.OrderID,
				Payload: payload,
			})
		}
	}
}

func (h *OrderWSHandler) sendPong(c *wsinfra.Client) {
	msg, _ := json.Marshal(map[string]string{"type": "pong"})
	select {
	case c.Send <- msg:
	default:
	}
}

func (h *OrderWSHandler) writePump(c *wsinfra.Client) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		_ = c.Conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.Send:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.Conn.WriteMessage(gws.CloseMessage, []byte{})
				return
			}
			if err := c.Conn.WriteMessage(gws.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(gws.PingMessage, nil); err != nil {
				return
			}
		}
	}
}