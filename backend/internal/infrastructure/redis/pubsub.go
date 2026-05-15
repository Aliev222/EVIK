package redis

import (
	"context"
	"encoding/json"

	orderdomain "evik/backend/internal/domain/order"
	"github.com/redis/go-redis/v9"
)

type OrderEventPublisher struct {
	client  *redis.Client
	channel string
}

func NewOrderEventPublisher(client *redis.Client, channel string) *OrderEventPublisher {
	return &OrderEventPublisher{client: client, channel: channel}
}

func (p *OrderEventPublisher) Publish(ctx context.Context, event orderdomain.Event) error {
	payload, err := json.Marshal(event)
	if err != nil {
		return err
	}
	return p.client.Publish(ctx, p.channel, payload).Err()
}

func (p *OrderEventPublisher) Subscribe(ctx context.Context) *redis.PubSub {
	return p.client.Subscribe(ctx, p.channel)
}
