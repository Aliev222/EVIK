package http

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Sentinel errors let callers distinguish server misconfiguration and upstream
// transport failures from genuine client validation errors, so HTTP handlers
// can return accurate status codes (503/502/401) instead of a blanket 400.
var (
	// ErrCredentialsNotConfigured signals the server is missing YooKassa shop
	// credentials. This is a server misconfiguration, never a client mistake.
	ErrCredentialsNotConfigured = errors.New("yookassa credentials are not configured")
	// ErrUpstreamUnavailable signals a network/transport failure reaching YooKassa.
	ErrUpstreamUnavailable = errors.New("yookassa upstream unavailable")
	// ErrUpstreamUnauthorized signals YooKassa rejected our credentials (HTTP 401/403).
	ErrUpstreamUnauthorized = errors.New("yookassa upstream rejected credentials")
)

type YooKassaClient struct {
	baseURL         string
	shopID          string
	secretKey       string
	returnURL       string
	payoutGatewayID string
	payoutSecretKey string
	payoutMode      string
	client          *http.Client
}

type YooKassaPaymentRequest struct {
	Amount         int64
	Currency       string
	Description    string
	IdempotencyKey string
	Metadata       map[string]string
	Capture        bool
	SaveMethod     bool
}

type YooKassaPaymentResponse struct {
	ID              string
	Status          string
	ConfirmationURL string
	Paid            bool
}

type YooKassaPayoutRequest struct {
	Amount              int64
	Currency            string
	ProviderRecipientID string
	Description         string
	IdempotencyKey      string
}

type YooKassaPayoutResponse struct {
	ID     string
	Status string
}

func NewYooKassaClient(shopID, secretKey, returnURL, payoutGatewayID, payoutSecretKey, payoutMode string) *YooKassaClient {
	if payoutMode == "" {
		payoutMode = "sandbox"
	}
	return &YooKassaClient{
		baseURL:         "https://api.yookassa.ru/v3",
		shopID:          shopID,
		secretKey:       secretKey,
		returnURL:       returnURL,
		payoutGatewayID: payoutGatewayID,
		payoutSecretKey: payoutSecretKey,
		payoutMode:      payoutMode,
		client:          &http.Client{Timeout: 15 * time.Second},
	}
}

func (c *YooKassaClient) CreatePayment(ctx context.Context, req YooKassaPaymentRequest) (*YooKassaPaymentResponse, error) {
	if c.shopID == "" || c.secretKey == "" {
		return nil, ErrCredentialsNotConfigured
	}
	payload := map[string]any{
		"amount": map[string]string{
			"value":    formatKopecks(req.Amount),
			"currency": req.Currency,
		},
		"capture": req.Capture,
		"confirmation": map[string]string{
			"type":       "redirect",
			"return_url": c.returnURL,
		},
		"description": req.Description,
		"metadata":    req.Metadata,
	}
	if req.SaveMethod {
		payload["save_payment_method"] = true
	}
	var out struct {
		ID           string `json:"id"`
		Status       string `json:"status"`
		Paid         bool   `json:"paid"`
		Confirmation struct {
			ConfirmationURL string `json:"confirmation_url"`
		} `json:"confirmation"`
	}
	if err := c.doJSON(ctx, http.MethodPost, "/payments", req.IdempotencyKey, c.basicAuth(), payload, &out); err != nil {
		return nil, err
	}
	return &YooKassaPaymentResponse{
		ID:              out.ID,
		Status:          out.Status,
		ConfirmationURL: out.Confirmation.ConfirmationURL,
		Paid:            out.Paid,
	}, nil
}

func (c *YooKassaClient) CreatePayout(ctx context.Context, req YooKassaPayoutRequest) (*YooKassaPayoutResponse, error) {
	if c.payoutMode != "live" {
		return &YooKassaPayoutResponse{
			ID:     "sandbox-" + req.IdempotencyKey,
			Status: "succeeded",
		}, nil
	}
	return nil, errors.New("live yookassa payout payloads for card/sbp/bank_account are not implemented; YOOKASSA_PAYOUT_MODE must remain sandbox")
}

func (c *YooKassaClient) createLegacyPayout(ctx context.Context, req YooKassaPayoutRequest) (*YooKassaPayoutResponse, error) {
	if c.payoutSecretKey == "" {
		return nil, errors.New("yookassa payout credentials are not configured")
	}
	payload := map[string]any{
		"amount": map[string]string{
			"value":    formatKopecks(req.Amount),
			"currency": req.Currency,
		},
		"recipient": map[string]string{
			"recipient_id": req.ProviderRecipientID,
		},
		"description": req.Description,
	}
	if c.payoutGatewayID != "" {
		payload["gateway_id"] = c.payoutGatewayID
	}
	var out struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	authID := c.payoutGatewayID
	if authID == "" {
		authID = c.shopID
	}
	payoutAuth := "Basic " + base64.StdEncoding.EncodeToString([]byte(authID+":"+c.payoutSecretKey))
	if err := c.doJSON(ctx, http.MethodPost, "/payouts", req.IdempotencyKey, payoutAuth, payload, &out); err != nil {
		return nil, err
	}
	return &YooKassaPayoutResponse{ID: out.ID, Status: out.Status}, nil
}

func (c *YooKassaClient) doJSON(ctx context.Context, method, path, idempotencyKey, authHeader string, payload any, out any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Idempotence-Key", idempotencyKey)
	request.Header.Set("Authorization", authHeader)
	response, err := c.client.Do(request)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUpstreamUnavailable, err)
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return fmt.Errorf("%w: status=%d body=%s", ErrUpstreamUnauthorized, response.StatusCode, string(responseBody))
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("yookassa api error: status=%d body=%s", response.StatusCode, string(responseBody))
	}
	return json.Unmarshal(responseBody, out)
}

func (c *YooKassaClient) GetPayment(ctx context.Context, paymentID string) (*YooKassaPaymentResponse, error) {
	if c.shopID == "" || c.secretKey == "" {
		return nil, ErrCredentialsNotConfigured
	}
	var out struct {
		ID           string `json:"id"`
		Status       string `json:"status"`
		Paid         bool   `json:"paid"`
		Confirmation struct {
			ConfirmationURL string `json:"confirmation_url"`
		} `json:"confirmation"`
	}
	if err := c.doGET(ctx, "/payments/"+paymentID, c.basicAuth(), &out); err != nil {
		return nil, err
	}
	return &YooKassaPaymentResponse{
		ID:              out.ID,
		Status:          out.Status,
		ConfirmationURL: out.Confirmation.ConfirmationURL,
		Paid:            out.Paid,
	}, nil
}

func (c *YooKassaClient) doGET(ctx context.Context, path, authHeader string, out any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, http.NoBody)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", authHeader)
	response, err := c.client.Do(request)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUpstreamUnavailable, err)
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return fmt.Errorf("%w: status=%d body=%s", ErrUpstreamUnauthorized, response.StatusCode, string(responseBody))
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("yookassa api error: status=%d body=%s", response.StatusCode, string(responseBody))
	}
	return json.Unmarshal(responseBody, out)
}

func (c *YooKassaClient) basicAuth() string {
	token := base64.StdEncoding.EncodeToString([]byte(c.shopID + ":" + c.secretKey))
	return "Basic " + token
}

func formatKopecks(value int64) string {
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}
