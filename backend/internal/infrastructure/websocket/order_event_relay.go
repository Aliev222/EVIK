package wsinfra

import (
	"context"
	"encoding/json"
	"log"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/redis"
)

// DriverCityGetter looks up the cached city for a connected driver.
type DriverCityGetter interface {
	GetDriverCity(ctx context.Context, driverID string) (string, error)
}

type OrderEventRelay struct {
	hub        *Hub
	pubsub     *redis.OrderEventPublisher
	cityGetter DriverCityGetter
	logger     *log.Logger
}

func NewOrderEventRelay(hub *Hub, pubsub *redis.OrderEventPublisher, cityGetter DriverCityGetter, logger *log.Logger) *OrderEventRelay {
	return &OrderEventRelay{hub: hub, pubsub: pubsub, cityGetter: cityGetter, logger: logger}
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
		r.logger.Printf("relay: failed to parse event: %v", err)
		r.hub.Broadcast([]byte(payload))
		return
	}

	pm, _ := event.Payload.(map[string]any)
	userID, _ := pm["user_id"].(string)
	driverID, _ := pm["driver_id"].(string)

	switch event.Type {
	case orderdomain.EventSearching:
		cityID := extractOrderCityID(pm)
		if cityID != "" && r.cityGetter != nil {
			r.hub.SendToDriversWhere(func(c *Client) bool {
				city, err := r.cityGetter.GetDriverCity(context.Background(), c.UserID)
				return err == nil && city == cityID
			}, []byte(payload))
			r.logger.Printf("relay: searching sent to city %s for order %s", cityID, event.OrderID)
		} else {
			r.hub.SendToDriversWhere(func(_ *Client) bool { return true }, []byte(payload))
		}

	case orderdomain.EventOrderExpanded:
		// Broadcast to all connected drivers; client-side distance filtering applies.
		r.hub.SendToDriversWhere(func(_ *Client) bool { return true }, []byte(payload))
		r.logger.Printf("relay: order_expanded broadcast for order %s", event.OrderID)

	default:
		if userID != "" {
			r.hub.SendToUser(userID, []byte(payload))
		}
		if driverID != "" {
			r.hub.SendToDriver(driverID, []byte(payload))
		}
		if userID == "" && driverID == "" {
			r.hub.Broadcast([]byte(payload))
		}
	}
}

func extractOrderCityID(pm map[string]any) string {
	if pm == nil {
		return ""
	}
	orderMap, _ := pm["order"].(map[string]any)
	if orderMap == nil {
		return ""
	}
	cityID, _ := orderMap["city_id"].(string)
	return cityID
}
