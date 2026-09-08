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
	results []geocoding.CitySearchResult
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

func (f *fakeReverseGeocoder) Search(_ context.Context, _ string, _ int) ([]geocoding.CitySearchResult, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.results, nil
}

func performReverse(geocoder Geocoder, query string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/geocode/reverse?"+query, nil)
	rec := httptest.NewRecorder()
	handler := NewGeocodingHandler(geocoder).Reverse
	handler(rec, req)
	return rec
}

func performSearch(geocoder Geocoder, query string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/geocode/search?"+query, nil)
	rec := httptest.NewRecorder()
	NewGeocodingHandler(geocoder).Search(rec, req)
	return rec
}

func TestSearchGeocodeOk(t *testing.T) {
	rec := performSearch(&fakeReverseGeocoder{results: []geocoding.CitySearchResult{{
		DisplayName: "ул. Пушкина, 1, Махачкала",
		CenterLat:   42.984,
		CenterLng:   47.505,
	}}}, "q=%D0%9F%D1%83%D1%88%D0%BA%D0%B8%D0%BD%D0%B0&limit=1")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body struct {
		Results []struct {
			DisplayName string  `json:"display_name"`
			Lat         float64 `json:"lat"`
			Lng         float64 `json:"lng"`
		} `json:"results"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Results) != 1 || body.Results[0].DisplayName != "ул. Пушкина, 1, Махачкала" {
		t.Fatalf("results = %#v, want normalized search result", body.Results)
	}
	if body.Results[0].Lat != 42.984 || body.Results[0].Lng != 47.505 {
		t.Fatalf("coordinates = (%v,%v), want (42.984,47.505)", body.Results[0].Lat, body.Results[0].Lng)
	}
}

func TestSearchGeocodeValidatesQuery(t *testing.T) {
	for name, query := range map[string]string{
		"missing":   "",
		"too short": "q=%D1%83%D0%BB",
	} {
		t.Run(name, func(t *testing.T) {
			rec := performSearch(&fakeReverseGeocoder{}, query)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", rec.Code)
			}
		})
	}
}

func TestSearchGeocodeProviderError(t *testing.T) {
	rec := performSearch(&fakeReverseGeocoder{err: errors.New("boom")}, "q=city")
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "boom") {
		t.Fatalf("body = %q, raw provider error leaked to client", rec.Body.String())
	}
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
	// The raw provider error must not leak; the client gets a generic message.
	if strings.Contains(rec.Body.String(), "boom") {
		t.Fatalf("body = %q, raw provider error leaked to client", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "upstream service error") {
		t.Fatalf("body = %q, want safe upstream service error", rec.Body.String())
	}
}
