package http

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"

	"evik/backend/internal/domain/settings"
)

type SettingsHandler struct {
	repo settings.Repository
}

func NewSettingsHandler(repo settings.Repository) *SettingsHandler {
	return &SettingsHandler{repo: repo}
}

func (h *SettingsHandler) List(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.List(r.Context())
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// settingKeyType classifies a known platform setting key so that Update can
// apply strict per-key validation before persisting anything.
type settingKeyType int

const (
	settingTypeMoney settingKeyType = iota
	settingTypePercent
	settingTypeNonNegativeInt
	settingTypePayoutMode
)

// knownSettings is the fixed, allowlisted set of platform settings. Every key
// here is either read by production code (finance.go, dispatch_scheduler.go) or
// seeded by migrations/20260602_seed_data.sql. There is no dynamic-key consumer
// in the project, so unknown keys are rejected with 400.
var knownSettings = map[string]settingKeyType{
	"commission_percent":                settingTypePercent,
	"driver_subscription_daily_price":   settingTypeMoney,
	"driver_subscription_weekly_price":  settingTypeMoney,
	"driver_subscription_monthly_price": settingTypeMoney,
	"min_withdrawal_kopecks":            settingTypeMoney,
	"offer_timeout_seconds":             settingTypeNonNegativeInt,
	"dispatch_round_limit":              settingTypeNonNegativeInt,
	"payout_mode":                       settingTypePayoutMode,
}

// validateSettingKeyValue checks a decoded settings update against the fixed
// key set and the per-key invariants. It returns a human-readable error meant
// for HTTP 400 responses.
func validateSettingKeyValue(key string, value any) error {
	kind, known := knownSettings[key]
	if !known {
		return fmt.Errorf("unknown setting key %q", key)
	}
	switch kind {
	case settingTypeMoney:
		n, ok := parseIntSettingValue(value)
		if !ok {
			return fmt.Errorf("%s: value must be a whole number of kopecks, got %T", key, value)
		}
		if n <= 0 {
			return fmt.Errorf("%s: value must be greater than 0, got %d", key, n)
		}
	case settingTypePercent:
		n, ok := parseIntSettingValue(value)
		if !ok {
			return fmt.Errorf("%s: value must be an integer, got %T", key, value)
		}
		if n < 0 || n > 100 {
			return fmt.Errorf("%s: value must be between 0 and 100, got %d", key, n)
		}
	case settingTypeNonNegativeInt:
		n, ok := parseIntSettingValue(value)
		if !ok {
			return fmt.Errorf("%s: value must be a non-negative integer, got %T", key, value)
		}
		if n < 0 {
			return fmt.Errorf("%s: value must not be negative, got %d", key, n)
		}
	case settingTypePayoutMode:
		mode, ok := value.(string)
		if !ok {
			return fmt.Errorf("%s: value must be a string, got %T", key, value)
		}
		mode = strings.TrimSpace(mode)
		if mode != "auto" && mode != "manual" {
			return fmt.Errorf("%s: value must be one of \"auto\" or \"manual\", got %q", key, mode)
		}
	}
	return nil
}

// parseIntSettingValue interprets a decoded JSON value (number or numeric
// string) as an integer. Non-integral numbers and non-numeric values are
// rejected. Both float64 (from a JSON number) and string forms are accepted to
// stay compatible with how settings are read elsewhere (e.g. commission_percent
// stored as "15.00").
func parseIntSettingValue(value any) (int64, bool) {
	switch v := value.(type) {
	case float64:
		if math.Trunc(v) != v {
			return 0, false
		}
		return int64(v), true
	case string:
		s := strings.TrimSpace(v)
		if n, err := strconv.ParseInt(s, 10, 64); err == nil {
			return n, true
		}
		if f, err := strconv.ParseFloat(s, 64); err == nil && math.Trunc(f) == f {
			return int64(f), true
		}
		return 0, false
	default:
		return 0, false
	}
}

func (h *SettingsHandler) Update(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Key   string `json:"key"`
		Value any    `json:"value"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if req.Key == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "key is required"})
		return
	}
	if err := validateSettingKeyValue(req.Key, req.Value); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if err := h.repo.Upsert(r.Context(), req.Key, req.Value); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}
