package payment

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
)

// yooKassaCIDRs lists the IP ranges YooKassa sends webhook requests from.
// Source: https://yookassa.ru/docs/support/merchant/payment-notification#ip
var yooKassaCIDRs = []string{
	"185.71.76.0/27",
	"185.71.77.0/27",
	"77.75.153.0/25",
	"77.75.154.128/25",
	"77.75.156.11/32",
	"77.75.156.35/32",
	"2a02:5180::/32",
}

// YooKassaVerifier implements WebhookVerifier for YooKassa (ЮKassa).
// Source verification is done by checking the sender IP against YooKassa's
// published CIDR allowlist.
type YooKassaVerifier struct{}

func NewYooKassaVerifier() *YooKassaVerifier {
	return &YooKassaVerifier{}
}

func (YooKassaVerifier) Verify(r *http.Request, _ []byte) error {
	clientIP := clientIPFromRequest(r)
	ip := net.ParseIP(clientIP)
	if ip == nil {
		return errors.New("cannot parse client IP")
	}
	for _, cidr := range yooKassaCIDRs {
		_, network, err := net.ParseCIDR(cidr)
		if err != nil {
			continue
		}
		if network.Contains(ip) {
			return nil
		}
	}
	return fmt.Errorf("IP %s is not in YooKassa allowlist", clientIP)
}

// clientIPFromRequest extracts the client IP from a request.
// It tries X-Real-IP first (trusted proxy), then falls back to RemoteAddr.
//
// TODO(B-01): при переезде на VPS настроить доверенный прокси (nginx X-Real-IP)
//
//	и указать реальный источник IP. Сейчас — базовый fallback.
func clientIPFromRequest(r *http.Request) string {
	if xrip := r.Header.Get("X-Real-IP"); xrip != "" {
		return xrip
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func (YooKassaVerifier) ParseEvent(body []byte) (WebhookEvent, error) {
	var raw struct {
		Type   string `json:"type"`
		Event  string `json:"event"`
		Object struct {
			ID            string            `json:"id"`
			Status        string            `json:"status"`
			Paid          bool              `json:"paid"`
			Metadata      map[string]string `json:"metadata"`
			PaymentMethod struct {
				ID    string `json:"id"`
				Saved bool   `json:"saved"`
				Title string `json:"title"`
				Card  struct {
					Last4       string `json:"last4"`
					ExpiryMonth string `json:"expiry_month"`
					ExpiryYear  string `json:"expiry_year"`
					CardType    string `json:"card_type"`
				} `json:"card"`
			} `json:"payment_method"`
		} `json:"object"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return WebhookEvent{}, err
	}

	eventType := raw.Event
	if eventType == "" {
		eventType = raw.Type
	}

	ev := WebhookEvent{
		EventID:   eventType + ":" + raw.Object.ID,
		Provider:  "yookassa",
		EventType: eventType,
		PaymentID: raw.Object.ID,
		Status:    raw.Object.Status,
		Paid:      raw.Object.Paid || raw.Object.Status == "succeeded",
	}
	if raw.Object.Metadata != nil {
		ev.Purpose = raw.Object.Metadata["purpose"]
		ev.OrderID = raw.Object.Metadata["order_id"]
	}
	ev.PaymentMethodSaved = raw.Object.PaymentMethod.Saved
	ev.PaymentMethodID = raw.Object.PaymentMethod.ID
	ev.CardLast4 = raw.Object.PaymentMethod.Card.Last4
	ev.CardExpiryMonth = raw.Object.PaymentMethod.Card.ExpiryMonth
	ev.CardExpiryYear = raw.Object.PaymentMethod.Card.ExpiryYear
	ev.CardType = raw.Object.PaymentMethod.Card.CardType
	ev.CardHolder = raw.Object.PaymentMethod.Title
	return ev, nil
}
