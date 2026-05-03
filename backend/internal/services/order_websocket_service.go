package services

import (
	"encoding/json"
	"log"

	orderdomain "evik/backend/internal/domain/order"
	ws "evik/backend/internal/transport/ws"
)

// OrderWebSocketService интегрирует заказы с WebSocket уведомлениями
type OrderWebSocketService struct {
	hub    *ws.EnhancedHub
	logger *log.Logger
}

func NewOrderWebSocketService(hub *ws.EnhancedHub, logger *log.Logger) *OrderWebSocketService {
	return &OrderWebSocketService{
		hub:    hub,
		logger: logger,
	}
}

// NotifyOrderStatusChanged отправляет уведомление об изменении статуса заказа
func (s *OrderWebSocketService) NotifyOrderStatusChanged(order *orderdomain.Order, oldStatus orderdomain.Status) {
	// Логируем изменение
	s.logger.Printf("Order %s status changed: %s -> %s", order.ID, oldStatus, order.Status)

	// Отправляем WebSocket уведомление
	s.hub.BroadcastOrderUpdate(
		order.ID,
		string(order.Status),
		order.UserID,
		getStringPointer(order.DriverID),
	)

	// Дополнительные уведомления в зависимости от статуса
	switch order.Status {
	case orderdomain.StatusAccepted:
		s.notifyOrderAccepted(order)
	case orderdomain.StatusArrived:
		s.notifyDriverArrived(order)
	case orderdomain.StatusInProgress:
		s.notifyEvacuationStarted(order)
	case orderdomain.StatusCompleted:
		s.notifyOrderCompleted(order)
	case orderdomain.StatusCancelled:
		s.notifyOrderCancelled(order)
	}
}

// NotifyDriverLocationUpdate отправляет обновление местоположения водителя
func (s *OrderWebSocketService) NotifyDriverLocationUpdate(orderID, driverID, clientID string, lat, lng float64) {
	s.hub.BroadcastDriverLocation(orderID, driverID, clientID, lat, lng)
}

// NotifyNewOrderAvailable уведомляет водителей о новом доступном заказе
func (s *OrderWebSocketService) NotifyNewOrderAvailable(order *orderdomain.Order) {
	// Создаем сообщение для водителей
	message := ws.WSMessage{
		Type: "new_order_available",
		Payload: map[string]interface{}{
			"order_id":    order.ID,
			"pickup_lat":  order.Pickup.Lat,
			"pickup_lng":  order.Pickup.Lng,
			"dropoff_lat": order.Dropoff.Lat,
			"dropoff_lng": order.Dropoff.Lng,
			"created_at":  order.CreatedAt.Format("2006-01-02T15:04:05.000Z07:00"),
		},
		Timestamp: order.CreatedAt,
	}

	msgBytes, err := json.Marshal(message)
	if err != nil {
		s.logger.Printf("Failed to marshal new order message: %v", err)
		return
	}

	// Отправляем всем подключенным водителям (можно улучшить геофильтрацией)
	s.hub.Broadcast(msgBytes)
}

func (s *OrderWebSocketService) notifyOrderAccepted(order *orderdomain.Order) {
	// Отправляем клиенту детальную информацию о водителе
	message := ws.WSMessage{
		Type: "driver_assigned",
		Payload: map[string]interface{}{
			"order_id":  order.ID,
			"driver_id": getStringPointer(order.DriverID),
			"message":   "Водитель принял ваш заказ и уже едет к вам",
			"eta":       "15-20 минут", // В продакшене - реальный расчет
		},
		Timestamp: order.UpdatedAt,
	}

	msgBytes, _ := json.Marshal(message)
	s.hub.SendToUser(order.UserID, msgBytes)
}

func (s *OrderWebSocketService) notifyDriverArrived(order *orderdomain.Order) {
	// Уведомляем клиента о прибытии водителя
	message := ws.WSMessage{
		Type: "driver_arrived",
		Payload: map[string]interface{}{
			"order_id": order.ID,
			"message":  "Водитель прибыл к месту подачи",
		},
		Timestamp: order.UpdatedAt,
	}

	msgBytes, _ := json.Marshal(message)
	s.hub.SendToUser(order.UserID, msgBytes)
}

func (s *OrderWebSocketService) notifyEvacuationStarted(order *orderdomain.Order) {
	message := ws.WSMessage{
		Type: "evacuation_started",
		Payload: map[string]interface{}{
			"order_id": order.ID,
			"message":  "Эвакуация началась. Водитель направляется к месту назначения",
		},
		Timestamp: order.UpdatedAt,
	}

	msgBytes, _ := json.Marshal(message)
	s.hub.SendToUser(order.UserID, msgBytes)
}

func (s *OrderWebSocketService) notifyOrderCompleted(order *orderdomain.Order) {
	// Уведомления и клиенту, и водителю
	clientMessage := ws.WSMessage{
		Type: "order_completed",
		Payload: map[string]interface{}{
			"order_id": order.ID,
			"message":  "Заказ успешно завершен. Спасибо за использование EVIK!",
		},
		Timestamp: order.UpdatedAt,
	}

	driverMessage := ws.WSMessage{
		Type: "order_completed",
		Payload: map[string]interface{}{
			"order_id": order.ID,
			"message":  "Заказ завершен. Вы свободны для новых заказов",
		},
		Timestamp: order.UpdatedAt,
	}

	clientMsgBytes, _ := json.Marshal(clientMessage)
	driverMsgBytes, _ := json.Marshal(driverMessage)

	s.hub.SendToUser(order.UserID, clientMsgBytes)
	if order.DriverID != nil {
		s.hub.SendToUser(*order.DriverID, driverMsgBytes)
	}
}

func (s *OrderWebSocketService) notifyOrderCancelled(order *orderdomain.Order) {
	message := ws.WSMessage{
		Type: "order_cancelled",
		Payload: map[string]interface{}{
			"order_id":     order.ID,
			"message":      "Заказ был отменен",
			"cancelled_at": order.CancelledAt.Format("2006-01-02T15:04:05.000Z07:00"),
		},
		Timestamp: order.UpdatedAt,
	}

	msgBytes, _ := json.Marshal(message)

	// Уведомляем и клиента, и водителя если он назначен
	s.hub.SendToUser(order.UserID, msgBytes)
	if order.DriverID != nil {
		s.hub.SendToUser(*order.DriverID, msgBytes)
	}
}

// Helper function для работы с *string
func getStringPointer(ptr *string) string {
	if ptr == nil {
		return ""
	}
	return *ptr
}