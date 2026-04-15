package wsinfra

import (
	"context"

	"evik/backend/internal/infrastructure/redis"
)

type OrderEventRelay struct {
	hub    *Hub
	pubsub *redis.OrderEventPublisher
}

func NewOrderEventRelay(hub *Hub, pubsub *redis.OrderEventPublisher) *OrderEventRelay {
	return &OrderEventRelay{hub: hub, pubsub: pubsub}
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
				r.hub.Broadcast([]byte(msg.Payload))
			}
		}
	}
}
