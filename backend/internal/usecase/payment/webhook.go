package payment

import "net/http"

// WebhookEvent carries the parsed webhook payload after provider-specific
// decoding. The Verifier extracts these fields; the handler logic is
// provider-agnostic.
type WebhookEvent struct {
	EventID   string
	Provider  string
	EventType string
	PaymentID string
	Status    string
	Paid      bool

	// Metadata
	Purpose string
	OrderID string

	// Card binding
	PaymentMethodSaved bool
	PaymentMethodID    string
	CardLast4          string
	CardExpiryMonth    string
	CardExpiryYear     string
	CardType           string
	CardHolder         string
}

// WebhookVerifier abstracts payment-provider-specific webhook verification
// and event parsing. Each provider (YooKassa, Tochka, Cyclops) provides its
// own implementation.
type WebhookVerifier interface {
	// Verify checks that the request originates from a legitimate provider
	// source (IP allowlist, cryptographic signature, etc.).
	Verify(r *http.Request, body []byte) error

	// ParseEvent decodes the provider-specific JSON body into a
	// provider-agnostic WebhookEvent.
	ParseEvent(body []byte) (WebhookEvent, error)
}
