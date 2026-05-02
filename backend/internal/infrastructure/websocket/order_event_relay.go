package wsinfra

import (
	"context"
	"encoding/json"
	"log"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/redis"
)

type OrderEventRelay struct {
	hub    *Hub
	pubsub *redis.OrderEventPublisher
	logger *log.Logger
}

func NewOrderEventRelay(hub *Hub, pubsub *redis.OrderEventPublisher, logger *log.Logger) *OrderEventRelay {
	return &OrderEventRelay{hub: hub, pubsub: pubsub, logger: logger}
}

func (r *OrderEventRelay) Run(ctx context.Context) {
	sub := r.pubsub.Subscribe(ctx)
	ch := sub.Channel()
	for {
		select {
		case <-ctx.Done():
			_ = sub.Close()
			return
		case msg := <-ch:
			if msg != nil {
				r.handleEvent(msg.Payload)
			}
		}
	}
}

func (r *OrderEventRelay) handleEvent(payload string) {
	var event orderdomain.Event
	if err := json.Unmarshal([]byte(payload), &event); err != nil {
		r.logger.Printf("Failed to parse event: %v", err)
		// Fallback to broadcasting raw payload
		r.hub.Broadcast([]byte(payload))
		return
	}

	switch event.Type {
	case orderdomain.EventSearching:
		// Notify all available drivers about new order
		r.hub.Broadcast([]byte(payload))
		r.logger.Printf("Broadcasting new order to all drivers: %s", event.OrderID)

	case orderdomain.EventAccepted:
		// Notify specific client about accepted order
		if payloadMap, ok := event.Payload.(map[string]any); ok {
			if userID, ok := payloadMap["user_id"].(string); ok {
				r.hub.SendToUser(userID, []byte(payload))
				r.logger.Printf("Sent order accepted event to client %s for order %s", userID, event.OrderID)
			} else {
				// Fallback to broadcast
				r.hub.Broadcast([]byte(payload))
			}
		} else {
			// Fallback to broadcast
			r.hub.Broadcast([]byte(payload))
		}

	default:
		// For other events, broadcast to all clients
		r.hub.Broadcast([]byte(payload))
	}
}
