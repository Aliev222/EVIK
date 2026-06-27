// Package fcm wraps the Firebase Admin SDK (firebase.google.com/go/v4) and
// fans push notifications out to every active device token registered for a
// user or for the entire available-driver pool.
//
// The package intentionally exposes a small PushSender interface so usecase
// code can be exercised in tests against a stub without dragging Firebase
// into the test binary. Construction is split between New (real Firebase
// client) and NewNoop (silent no-op for local development without the
// FIREBASE_CREDENTIALS_JSON secret).
package fcm

import (
	"context"
	"errors"
	"fmt"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// PushSender is the dependency surface consumed by order usecases.
type PushSender interface {
	SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error
	BroadcastToAvailableDrivers(ctx context.Context, title, body string, data map[string]string) error
	BroadcastToDriversInCity(ctx context.Context, cityID, title, body string, data map[string]string) error
}

// AreaBBoxLookup resolves a service-area ID to its bounding box.
type AreaBBoxLookup interface {
	GetAreaBBox(ctx context.Context, cityID string) (minLat, minLng, maxLat, maxLng float64, err error)
}

// DriverCityLocator returns IDs of drivers inside the given bounding box.
type DriverCityLocator interface {
	GetDriverIDsInBBox(ctx context.Context, minLat, minLng, maxLat, maxLng float64) ([]string, error)
}

// TokenLister is the slice of the user repository that the Sender needs.
type TokenLister interface {
	ListActiveDeviceTokens(ctx context.Context, userID string, role string) ([]string, error)
	ListAvailableDriverDeviceTokens(ctx context.Context) ([]string, error)
	ListDeviceTokensByDriverIDs(ctx context.Context, driverIDs []string) ([]string, error)
	RevokeDeviceToken(ctx context.Context, userID string, role string, fcmToken string, revokedAt time.Time) error
}

// Logger mirrors the shape used elsewhere in the codebase so we don't pull
// in a logging library here. Keeping it minimal keeps tests cheap.
type Logger interface {
	Info(msg string, keyvals ...any)
	Error(msg string, err error, keyvals ...any)
}

// messagingClient is the subset of *messaging.Client we actually call.
// Extracted so unit tests can stub Firebase out entirely.
type messagingClient interface {
	SendEachForMulticast(ctx context.Context, message *messaging.MulticastMessage) (*messaging.BatchResponse, error)
}

// Sender is the production Firebase-backed implementation of PushSender.
type Sender struct {
	client      messagingClient
	tokens      TokenLister
	areaLookup  AreaBBoxLookup
	cityLocator DriverCityLocator
	logger      Logger
	now         func() time.Time
}

// New initialises a Sender from a raw service-account JSON.
func New(ctx context.Context, credentialsJSON []byte, tokens TokenLister, areaLookup AreaBBoxLookup, cityLocator DriverCityLocator, logger Logger) (*Sender, error) {
	if len(credentialsJSON) == 0 {
		return nil, errors.New("fcm: empty credentials JSON")
	}
	if tokens == nil {
		return nil, errors.New("fcm: nil token lister")
	}
	app, err := firebase.NewApp(ctx, nil, option.WithCredentialsJSON(credentialsJSON))
	if err != nil {
		return nil, fmt.Errorf("fcm: init firebase app: %w", err)
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("fcm: init messaging client: %w", err)
	}
	return &Sender{
		client:      client,
		tokens:      tokens,
		areaLookup:  areaLookup,
		cityLocator: cityLocator,
		logger:      logger,
		now:         func() time.Time { return time.Now().UTC() },
	}, nil
}

// SendToUser fans the push out to every active device token registered for
// (userID, role). A nil/empty token list is not an error — the user simply
// has no devices subscribed.
func (s *Sender) SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error {
	tokens, err := s.tokens.ListActiveDeviceTokens(ctx, userID, role)
	if err != nil {
		return fmt.Errorf("fcm: list tokens for user %s/%s: %w", userID, role, err)
	}
	return s.sendMulticast(ctx, tokens, title, body, data, userID, role)
}

// BroadcastToAvailableDrivers sends the push to every driver who is online
// AND not currently engaged with another order. This intentionally fans out
// wider than the matcher: the matcher picks one winner, the push lets
// everyone else know an order exists so they can race to accept it.
func (s *Sender) BroadcastToAvailableDrivers(ctx context.Context, title, body string, data map[string]string) error {
	tokens, err := s.tokens.ListAvailableDriverDeviceTokens(ctx)
	if err != nil {
		return fmt.Errorf("fcm: list available driver tokens: %w", err)
	}
	// userID is empty for broadcast; role is "driver" so any token cleanup
	// on InvalidArgument/NotRegistered errors still targets the right scope.
	return s.sendMulticast(ctx, tokens, title, body, data, "", "driver")
}

// sendMulticast batches tokens into FCM's 500-token-per-call limit, fires
// each batch, and cleans up tokens that come back as NotRegistered or
// InvalidArgument so the same dead tokens don't bleed into every future
// broadcast.
func (s *Sender) sendMulticast(ctx context.Context, tokens []string, title, body string, data map[string]string, ownerUserID, ownerRole string) error {
	if len(tokens) == 0 {
		return nil
	}
	const fcmBatchLimit = 500
	for start := 0; start < len(tokens); start += fcmBatchLimit {
		end := start + fcmBatchLimit
		if end > len(tokens) {
			end = len(tokens)
		}
		batch := tokens[start:end]
		msg := &messaging.MulticastMessage{
			Tokens: batch,
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: data,
			Android: &messaging.AndroidConfig{
				Priority: "high",
			},
			APNS: &messaging.APNSConfig{
				Headers: map[string]string{"apns-priority": "10"},
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{Sound: "default"},
				},
			},
		}
		resp, err := s.client.SendEachForMulticast(ctx, msg)
		if err != nil {
			// Whole-batch failure: log and keep going; one bad batch should
			// not silence the rest of the broadcast.
			s.logger.Error("fcm batch send failed", err, "batch_size", len(batch))
			continue
		}
		s.handleResponses(ctx, batch, resp, ownerUserID, ownerRole)
	}
	return nil
}

// handleResponses walks per-token results and revokes tokens that FCM
// reported as permanently dead. Transient errors (Unavailable, Internal)
// are logged but left alone — the next push will retry.
func (s *Sender) handleResponses(ctx context.Context, batch []string, resp *messaging.BatchResponse, ownerUserID, ownerRole string) {
	if resp == nil {
		return
	}
	now := s.now()
	for i, r := range resp.Responses {
		if r.Success {
			continue
		}
		token := batch[i]
		if messaging.IsRegistrationTokenNotRegistered(r.Error) || messaging.IsInvalidArgument(r.Error) {
			// For a per-user push we know the owner; revoke directly. For a
			// broadcast we don't, so the cleanest revoke path is to leave
			// the token alone — the next per-user push that touches it
			// will revoke. Logging is enough here.
			if ownerUserID != "" {
				if err := s.tokens.RevokeDeviceToken(ctx, ownerUserID, ownerRole, token, now); err != nil {
					s.logger.Error("fcm revoke dead token failed", err, "user_id", ownerUserID, "role", ownerRole)
				}
				continue
			}
			s.logger.Info("fcm broadcast hit dead token (not revoked, owner unknown)", "role", ownerRole)
			continue
		}
		s.logger.Error("fcm per-token send failed", r.Error, "role", ownerRole)
	}
}

// BroadcastToDriversInCity sends a push to every online driver whose last
// known location is inside the service area identified by cityID.
func (s *Sender) BroadcastToDriversInCity(ctx context.Context, cityID, title, body string, data map[string]string) error {
	if s.areaLookup == nil || s.cityLocator == nil {
		return s.BroadcastToAvailableDrivers(ctx, title, body, data)
	}
	minLat, minLng, maxLat, maxLng, err := s.areaLookup.GetAreaBBox(ctx, cityID)
	if err != nil {
		return fmt.Errorf("fcm: get area bbox for %s: %w", cityID, err)
	}
	driverIDs, err := s.cityLocator.GetDriverIDsInBBox(ctx, minLat, minLng, maxLat, maxLng)
	if err != nil {
		return fmt.Errorf("fcm: get drivers in bbox: %w", err)
	}
	tokens, err := s.tokens.ListDeviceTokensByDriverIDs(ctx, driverIDs)
	if err != nil {
		return fmt.Errorf("fcm: list tokens for city drivers: %w", err)
	}
	return s.sendMulticast(ctx, tokens, title, body, data, "", "driver")
}

// NoopSender is wired in when FIREBASE_CREDENTIALS_JSON is empty.
type NoopSender struct{}

func NewNoop() NoopSender { return NoopSender{} }

func (NoopSender) SendToUser(context.Context, string, string, string, string, map[string]string) error {
	return nil
}

func (NoopSender) BroadcastToAvailableDrivers(context.Context, string, string, map[string]string) error {
	return nil
}

func (NoopSender) BroadcastToDriversInCity(context.Context, string, string, string, map[string]string) error {
	return nil
}
