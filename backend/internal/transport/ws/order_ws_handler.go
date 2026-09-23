package ws

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"evik/backend/internal/auth"
	chatdomain "evik/backend/internal/domain/chat"
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
	chatRepo       chatdomain.Repository
	clock          func() time.Time

	lastLocationPublish   map[string]time.Time
	lastLocationPublishMu sync.Mutex
	lastPublishedPhase    map[string]string
	lastLocationSeq       map[string]int64
	lastLocationSeqMu     sync.Mutex
	lastSampledAt         map[string]time.Time
	lastSampledAtMu       sync.Mutex
	lastAcceptedFix       map[string]acceptedLocationFix

	// Distance-based throttle: skip Redis writes when driver moved < minDistanceMeters
	lastLocation      map[string][2]float64 // driverID -> [lat, lng]
	lastLocationWrite map[string]time.Time
	lastLocationMu    sync.Mutex
	minDistanceMeters float64
}

type acceptedLocationFix struct {
	data      wsLocationData
	sampledAt time.Time
}

func (h *OrderWSHandler) SetChatRepository(repo chatdomain.Repository) { h.chatRepo = repo }

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
		lastPublishedPhase:    make(map[string]string),
		lastLocationSeq:       make(map[string]int64),
		lastSampledAt:         make(map[string]time.Time),
		lastAcceptedFix:       make(map[string]acceptedLocationFix),
		lastLocation:          make(map[string][2]float64),
		lastLocationWrite:     make(map[string]time.Time),
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
	Lat       float64  `json:"lat"`
	Lng       float64  `json:"lng"`
	Bearing   float64  `json:"bearing,omitempty"`
	Speed     float64  `json:"speed,omitempty"`
	SpeedMPS  *float64 `json:"speed_mps,omitempty"`
	AccuracyM *float64 `json:"accuracy_m,omitempty"`
	Status    string   `json:"status,omitempty"`
	OrderID   string   `json:"order_id,omitempty"`
	SampledAt string   `json:"sampled_at,omitempty"`
	IsMock    bool     `json:"is_mock"`
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
	case "chat.subscribe":
		h.handleChatSubscribe(c, msg.Data)
	case "chat.unsubscribe":
		h.handleChatUnsubscribe(c, msg.Data)
	case "chat.send":
		h.handleChatSend(c, msg.Data)
	case "register_driver", "register_client", "register_admin", "client_location_update", "create_order":
	default:
	}
}

type wsChatData struct {
	OrderID         string `json:"order_id"`
	ClientMessageID string `json:"client_message_id"`
	Text            string `json:"text"`
}

func (h *OrderWSHandler) handleChatSubscribe(c *wsinfra.Client, raw json.RawMessage) {
	if h.chatRepo == nil || h.hub == nil || (c.Role != string(auth.RoleClient) && c.Role != string(auth.RoleDriver)) {
		return
	}
	var data wsChatData
	if json.Unmarshal(raw, &data) != nil || strings.TrimSpace(data.OrderID) == "" {
		h.sendChatError(c, "invalid_chat_subscription")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	allowed, err := h.chatRepo.CanAccess(ctx, data.OrderID, c.UserID)
	if err != nil || !allowed {
		h.sendChatError(c, "forbidden")
		return
	}
	h.hub.SubscribeChat(c, data.OrderID)
	h.sendChatFrame(c, "chat.subscribed", map[string]string{"order_id": data.OrderID})
}

func (h *OrderWSHandler) handleChatUnsubscribe(c *wsinfra.Client, raw json.RawMessage) {
	if h.hub == nil {
		return
	}
	var data wsChatData
	if json.Unmarshal(raw, &data) == nil && data.OrderID != "" {
		h.hub.UnsubscribeChat(c, data.OrderID)
	}
}

func (h *OrderWSHandler) handleChatSend(c *wsinfra.Client, raw json.RawMessage) {
	if h.chatRepo == nil || (c.Role != string(auth.RoleClient) && c.Role != string(auth.RoleDriver)) {
		h.sendChatError(c, "forbidden")
		return
	}
	var data wsChatData
	if json.Unmarshal(raw, &data) != nil {
		h.sendChatError(c, "invalid_chat_message")
		return
	}
	data.Text = strings.TrimSpace(data.Text)
	data.OrderID = strings.TrimSpace(data.OrderID)
	data.ClientMessageID = strings.TrimSpace(data.ClientMessageID)
	if data.OrderID == "" || data.ClientMessageID == "" || len(data.ClientMessageID) > 128 || !utf8.ValidString(data.Text) || utf8.RuneCountInString(data.Text) == 0 || utf8.RuneCountInString(data.Text) > 1000 {
		h.sendChatError(c, "invalid_chat_message")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	m, err := h.chatRepo.Create(ctx, data.OrderID, c.UserID, data.ClientMessageID, data.Text)
	if err != nil {
		h.sendChatError(c, chatErrorCode(err))
		return
	}
	// Saved is the explicit contract for the acknowledgement; transport may
	// reconnect and replay the same client_message_id without duplication.
	h.sendChatFrame(c, "chat.ack", map[string]any{"message": m})
	if h.eventPublisher == nil {
		return
	}
	if err := h.eventPublisher.Publish(context.Background(), orderdomain.Event{Type: orderdomain.EventChatMessage, OrderID: m.OrderID, Payload: map[string]any{"message": m, "sender_id": m.SenderID, "recipient_id": m.RecipientID}}); err != nil {
		h.logger.Printf("ws: chat event publish failed for order=%s: %v", m.OrderID, err)
	}
}

func chatErrorCode(err error) string {
	switch {
	case errors.Is(err, chatdomain.ErrForbidden):
		return "forbidden"
	case errors.Is(err, chatdomain.ErrClosed):
		return "chat_closed"
	case errors.Is(err, chatdomain.ErrRateLimited):
		return "rate_limited"
	default:
		return "chat_unavailable"
	}
}
func (h *OrderWSHandler) sendChatError(c *wsinfra.Client, code string) {
	h.sendChatFrame(c, "chat.error", map[string]string{"code": code})
}
func (h *OrderWSHandler) sendChatFrame(c *wsinfra.Client, typ string, payload any) {
	b, _ := json.Marshal(map[string]any{"type": typ, "payload": payload})
	select {
	case c.Send <- b:
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
	if locData.AccuracyM != nil && (*locData.AccuracyM < 0 || *locData.AccuracyM > 5000) {
		h.logger.Printf("ws: invalid accuracy from driver=%s", c.UserID)
		return
	}

	now := h.clock()
	sampledAt := now
	if locData.SampledAt != "" {
		parsed, err := time.Parse(time.RFC3339Nano, locData.SampledAt)
		if err != nil || parsed.After(now.Add(30*time.Second)) {
			h.logger.Printf("ws: invalid sampled_at from driver=%s", c.UserID)
			return
		}
		sampledAt = parsed
	}
	h.lastSampledAtMu.Lock()
	lastSampledAt := h.lastSampledAt[c.UserID]
	lastFix, hasLastFix := h.lastAcceptedFix[c.UserID]
	isNewSample := lastSampledAt.IsZero() || sampledAt.After(lastSampledAt)
	if isNewSample && hasLastFix && isImplausibleLocationJump(lastFix, locData, sampledAt) {
		h.lastSampledAtMu.Unlock()
		h.logger.Printf("ws: implausible GPS jump rejected for driver=%s", c.UserID)
		return
	}
	if isNewSample {
		h.lastSampledAt[c.UserID] = sampledAt
		h.lastAcceptedFix[c.UserID] = acceptedLocationFix{data: locData, sampledAt: sampledAt}
	} else if hasLastFix {
		// An old/repeated packet may carry a newly authoritative order phase,
		// but it must never move the marker back to stale coordinates.
		locData = lastFix.data
		sampledAt = lastFix.sampledAt
	}
	h.lastSampledAtMu.Unlock()
	h.lastLocationSeqMu.Lock()
	h.lastLocationSeq[c.UserID]++
	seq := h.lastLocationSeq[c.UserID]
	h.lastLocationSeqMu.Unlock()

	if recorder, ok := h.orderRepo.(interface {
		RecordTripLocation(context.Context, string, string, float64, float64, time.Time) error
	}); ok && locData.OrderID != "" && isNewSample {
		if err := recorder.RecordTripLocation(
			context.Background(), locData.OrderID, c.UserID, locData.Lat, locData.Lng, sampledAt,
		); err != nil {
			h.logger.Printf("ws: trip location could not be recorded: %v", err)
		}
	}

	// Distance-based throttling is strictly an optimisation for the driver
	// geo index. It must never decide whether the order client sees telemetry:
	// a tow truck can legitimately move less than 50 m between GPS samples.
	h.lastLocationMu.Lock()
	prev, hasPrev := h.lastLocation[c.UserID]
	shouldWriteLocation := isNewSample
	if hasPrev {
		dist := haversineMeters(prev[0], prev[1], locData.Lat, locData.Lng)
		// The last confirmed geo write is held separately from publication
		// time; otherwise assigning publication time first makes this duration
		// zero and filters every small movement indefinitely.
		shouldWriteLocation = isNewSample && (dist >= h.minDistanceMeters || now.Sub(h.lastLocationWrite[c.UserID]) >= 30*time.Second)
	}
	if shouldWriteLocation || !hasPrev {
		h.lastLocation[c.UserID] = [2]float64{locData.Lat, locData.Lng}
		h.lastLocationWrite[c.UserID] = now
	}
	h.lastLocationMu.Unlock()

	if shouldWriteLocation && h.locationRepo != nil {
		if err := h.locationRepo.SaveLocation(context.Background(), c.UserID, location.Location{
			Lat:       locData.Lat,
			Lng:       locData.Lng,
			UpdatedAt: now,
		}); err != nil {
			h.logger.Printf("ws: SaveLocation error for driver=%s: %v", c.UserID, err)
		}
	}

	if locData.OrderID != "" && h.orderRepo != nil && h.eventPublisher != nil {
		ord, ordErr := h.orderRepo.GetByID(context.Background(), locData.OrderID)
		// Only notify the client of an order this driver is actually assigned
		// to. This keeps a driver from pushing their location to bystanders.
		if ordErr == nil && ord != nil && ord.UserID != "" && ord.DriverID != nil && *ord.DriverID == c.UserID && !isTerminalOrderStatus(ord.Status) {
			phase := markerPhaseForOrderStatus(ord.Status)
			h.lastLocationPublishMu.Lock()
			lastPub := h.lastLocationPublish[c.UserID]
			phaseChanged := h.lastPublishedPhase[c.UserID] != phase
			if !isNewSample && !phaseChanged {
				h.lastLocationPublishMu.Unlock()
				return
			}
			if now.Sub(lastPub) < 2*time.Second && !phaseChanged {
				h.lastLocationPublishMu.Unlock()
				return
			}
			h.lastLocationPublish[c.UserID] = now
			h.lastPublishedPhase[c.UserID] = phase
			h.lastLocationPublishMu.Unlock()
			payload := map[string]any{
				"driver_id": c.UserID,
				"user_id":   ord.UserID,
				"lat":       locData.Lat,
				"lng":       locData.Lng,
				"bearing":   locData.Bearing,
				"speed":     locData.Speed,
				// The server order state is authoritative. A stale HTTP or WS
				// heartbeat must not revert transport back to pickup phase.
				"status":      phase,
				"sampled_at":  sampledAt.UTC().Format(time.RFC3339Nano),
				"received_at": now.UTC().Format(time.RFC3339Nano),
				"seq":         seq,
			}
			if locData.SpeedMPS != nil {
				payload["speed_mps"] = *locData.SpeedMPS
			}
			if locData.AccuracyM != nil {
				payload["accuracy_m"] = *locData.AccuracyM
			}
			_ = h.eventPublisher.Publish(context.Background(), orderdomain.Event{
				Type:    orderdomain.EventDriverLocationUpdated,
				OrderID: locData.OrderID,
				Payload: payload,
			})
		}
	}
}

func isImplausibleLocationJump(previous acceptedLocationFix, next wsLocationData, sampledAt time.Time) bool {
	delta := sampledAt.Sub(previous.sampledAt).Seconds()
	if delta <= 0 {
		return false
	}
	distance := haversineMeters(previous.data.Lat, previous.data.Lng, next.Lat, next.Lng)
	previousAccuracy := 30.0
	if previous.data.AccuracyM != nil {
		previousAccuracy = *previous.data.AccuracyM
	}
	nextAccuracy := 30.0
	if next.AccuracyM != nil {
		nextAccuracy = *next.AccuracyM
	}
	// 70 m/s is deliberately above plausible road speed for a tow truck. The
	// accuracy allowance prevents ordinary GPS scatter from being discarded.
	allowedDistance := math.Max(150, 70*delta+previousAccuracy+nextAccuracy)
	return distance > allowedDistance
}

func markerPhaseForOrderStatus(status orderdomain.Status) string {
	switch status {
	case orderdomain.StatusArrived:
		return "waiting"
	case orderdomain.StatusInProgress, orderdomain.StatusAwaitingPayment:
		return "to_destination"
	default:
		return "to_pickup"
	}
}

func isTerminalOrderStatus(status orderdomain.Status) bool {
	return status == orderdomain.StatusCompleted || status == orderdomain.StatusCancelled || status == orderdomain.StatusNoDriverFound
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
