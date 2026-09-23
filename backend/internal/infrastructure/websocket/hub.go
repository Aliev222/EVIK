package wsinfra

import (
	"sync"

	gws "github.com/gorilla/websocket"
)

type Client struct {
	Conn       *gws.Conn
	Send       chan []byte
	UserID     string
	Role       string
	chatOrders map[string]struct{}
}

// SubscribeChat authorizes delivery at the WS connection level. The transport
// handler must validate the order participant before calling it.
func (h *Hub) SubscribeChat(c *Client, orderID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.clients[c]; !ok {
		return
	}
	if c.chatOrders == nil {
		c.chatOrders = make(map[string]struct{})
	}
	c.chatOrders[orderID] = struct{}{}
}

func (h *Hub) UnsubscribeChat(c *Client, orderID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(c.chatOrders, orderID)
}

// SendChatToUser delivers only to connections explicitly subscribed to this
// order. A fresh authorization check in the relay prevents stale assignments
// from receiving a queued cross-instance event.
func (h *Hub) SendChatToUser(userID, orderID string, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients {
		if c.UserID != userID {
			continue
		}
		if _, subscribed := c.chatOrders[orderID]; !subscribed {
			continue
		}
		select {
		case c.Send <- payload:
		default:
		}
	}
}

type Hub struct {
	clients    map[*Client]struct{}
	register   chan registerRequest
	unregister chan *Client
	broadcast  chan []byte
	mu         sync.RWMutex
}
type registerRequest struct {
	client *Client
	done   chan struct{}
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]struct{}),
		register:   make(chan registerRequest),
		unregister: make(chan *Client),
		broadcast:  make(chan []byte, 128),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case req := <-h.register:
			h.mu.Lock()
			h.clients[req.client] = struct{}{}
			h.mu.Unlock()
			close(req.done)
		case c := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[c]; ok {
				delete(h.clients, c)
				close(c.Send)
			}
			h.mu.Unlock()
		case msg := <-h.broadcast:
			h.mu.RLock()
			for c := range h.clients {
				select {
				case c.Send <- msg:
				default:
				}
			}
			h.mu.RUnlock()
		}
	}
}

func (h *Hub) Register(c *Client) {
	done := make(chan struct{})
	h.register <- registerRequest{client: c, done: done}
	<-done
}

func (h *Hub) Unregister(c *Client) {
	h.unregister <- c
}

func (h *Hub) Broadcast(payload []byte) {
	h.broadcast <- payload
}

// SendToDriver sends a message to a specific driver
func (h *Hub) SendToDriver(driverID string, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for c := range h.clients {
		if c.UserID == driverID && c.Role == "driver" {
			select {
			case c.Send <- payload:
			default:
				// Client buffer is full, skip
			}
		}
	}
}

// SendToUser sends a message to a specific user
func (h *Hub) SendToUser(userID string, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for c := range h.clients {
		if c.UserID == userID {
			select {
			case c.Send <- payload:
			default:
			}
		}
	}
}

// SendToDriversWhere sends payload to every connected driver client for which
// predicate returns true. Predicate is called under RLock — keep it cheap.
func (h *Hub) SendToDriversWhere(predicate func(c *Client) bool, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for c := range h.clients {
		if c.Role != "driver" {
			continue
		}
		if predicate(c) {
			select {
			case c.Send <- payload:
			default:
			}
		}
	}
}

// SendToRole sends payload to every connected client with the given role.
func (h *Hub) HasDriver(driverID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients {
		if c.UserID == driverID && c.Role == "driver" {
			return true
		}
	}
	return false
}

func (h *Hub) SendToRole(role string, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for c := range h.clients {
		if c.Role == role {
			select {
			case c.Send <- payload:
			default:
			}
		}
	}
}
