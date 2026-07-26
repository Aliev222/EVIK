package order

type EventType string

const (
	EventOrderCreated EventType = "order_created"
	EventSearching    EventType = "searching"
	EventAccepted     EventType = "order_accepted"
	EventArrived      EventType = "order_arrived"
	EventInProgress        EventType = "in_progress"
	EventAwaitingPayment   EventType = "awaiting_payment"
	EventCompleted         EventType = "completed"
	EventCancelled    EventType = "cancelled"
	EventNoDriverFound      EventType = "no_driver_found"
	EventOrderExpanded      EventType = "order_expanded"
	EventDriverLocationUpdated EventType = "driver_location"
	EventAdminDriverLocation   EventType = "admin_driver_location"
	EventPaymentMethodChanged  EventType = "payment_method_changed"
)

type Event struct {
	Type    EventType `json:"type"`
	OrderID string    `json:"order_id"`
	Payload any       `json:"payload,omitempty"`
}

func EventTypeFromStatus(status Status) EventType {
	switch status {
	case StatusSearching:
		return EventSearching
	case StatusAccepted:
		return EventAccepted
	case StatusArrived:
		return EventArrived
	case StatusInProgress:
		return EventInProgress
	case StatusAwaitingPayment:
		return EventAwaitingPayment
	case StatusCompleted:
		return EventCompleted
	case StatusCancelled:
		return EventCancelled
	default:
		return EventOrderCreated
	}
}
