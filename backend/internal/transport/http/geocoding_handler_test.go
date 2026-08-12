package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"evik/backend/internal/infrastructure/geocoding"
)

type fakeReverseGeocoder struct {
	address string
	err     error
}

func (f *fakeReverseGeocoder) Reverse(_ context.Context, _, _ float64) (*geocoding.ReverseResult, error) {
	if f.err != nil {
		return nil, f.err
	}
	if f.address == "" {
		return nil, geocoding.ErrReverseNotFound
	}
	return &geocoding.ReverseResult{DisplayName: f.address}, nil
}

func performReverse(geocoder ReverseGeocoder, query string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/geocode/reverse?"+query, nil)
	rec := httptest.NewRecorder()
	handler := NewGeocodingHandler(geocoder).Reverse
	handler(rec, req)
	return rec
}

func TestReverseGeocodeOk(t *testing.T) {
	rec := performReverse(&fakeReverseGeocoder{address: "ул. Пушкина, 1, Махачкала"}, "lat=42.984&lng=47.505")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["address"] != "ул. Пушкина, 1, Махачкала" {
		t.Fatalf("address = %q, want reverse result", body["address"])
	}
}

func TestReverseGeocodeMissingParams(t *testing.T) {
	for name, query := range map[string]string{
		"missing lat": "lng=42.0",
		"missing lng": "lat=42.0",
	} {
		t.Run(name, func(t *testing.T) {
			rec := performReverse(&fakeReverseGeocoder{address: "x"}, query)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", rec.Code)
			}
		})
	}
}

func TestReverseGeocodeInvalidParams(t *testing.T) {
	for name, query := range map[string]string{
		"non-numeric lat":  "lat=abc&lng=42.0",
		"non-numeric lng":  "lat=42.0&lng=def",
		"lat out of range": "lat=91&lng=42.0",
		"lng out of range": "lat=42.0&lng=181",
	} {
		t.Run(name, func(t *testing.T) {
			rec := performReverse(&fakeReverseGeocoder{address: "x"}, query)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", rec.Code)
			}
		})
	}
}

func TestReverseGeocodeNotFound(t *testing.T) {
	rec := performReverse(&fakeReverseGeocoder{address: ""}, "lat=42.0&lng=47.5")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestReverseGeocodeProviderError(t *testing.T) {
	rec := performReverse(&fakeReverseGeocoder{err: errors.New("boom")}, "lat=42.0&lng=47.5")
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "boom") {
		t.Fatalf("body = %q, want provider error surfaced", rec.Body.String())
	}
}
