package sms

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type SMSRuClient struct {
	apiID      string
	httpClient *http.Client
	baseURL    string
}

type SMSRuResponse struct {
	Status     string            `json:"status"`
	StatusCode int               `json:"status_code"`
	SMS        map[string]SMSInfo `json:"sms"`
	Balance    float64           `json:"balance"`
}

type SMSInfo struct {
	Status     string `json:"status"`
	StatusCode int    `json:"status_code"`
	SMSID      string `json:"sms_id"`
	Cost       string `json:"cost"`
}

func NewSMSRuClient(apiID string) *SMSRuClient {
	return &SMSRuClient{
		apiID: apiID,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		baseURL: "https://sms.ru/sms/send",
	}
}

func (c *SMSRuClient) SendSMS(phone, message string) error {
	// Prepare form data
	data := url.Values{}
	data.Set("api_id", c.apiID)
	data.Set("to", phone)
	data.Set("msg", message)
	data.Set("json", "1")

	// Create request
	req, err := http.NewRequest("POST", c.baseURL, strings.NewReader(data.Encode()))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	// Send request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send SMS: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	// Parse response
	var smsResp SMSRuResponse
	if err := json.Unmarshal(body, &smsResp); err != nil {
		return fmt.Errorf("failed to parse response: %w", err)
	}

	// Check status
	if smsResp.StatusCode != 100 {
		return fmt.Errorf("SMS.ru API error: status %d, %s", smsResp.StatusCode, smsResp.Status)
	}

	return nil
}

func (c *SMSRuClient) GetBalance() (float64, error) {
	req, err := http.NewRequest("GET", "https://sms.ru/my/balance?api_id="+c.apiID+"&json=1", nil)
	if err != nil {
		return 0, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("failed to get balance: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, fmt.Errorf("failed to read response: %w", err)
	}

	var balanceResp SMSRuResponse
	if err := json.Unmarshal(body, &balanceResp); err != nil {
		return 0, fmt.Errorf("failed to parse response: %w", err)
	}

	return balanceResp.Balance, nil
}