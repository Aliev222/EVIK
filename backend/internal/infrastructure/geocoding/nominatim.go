// Package geocoding wraps the OpenStreetMap Nominatim service for resolving
// city names into bounding boxes. Usage is governed by the Nominatim usage
// policy (https://operations.osmfoundation.org/policies/nominatim/), which
// requires an identifying User-Agent and a hard cap of one request per second.
package geocoding

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultBaseURL   = "https://nominatim.openstreetmap.org/search"
	defaultUserAgent = "AvroApp/1.0 (support@avro.app)"
	// minInterval enforces the Nominatim "max 1 request per second" policy.
	minInterval = time.Second
)

// ErrCityNotFound is returned when Nominatim has no result for the query.
var ErrCityNotFound = errors.New("geocoding: city not found")

// CitySearchResult is the normalized geocoding result for a single city.
type CitySearchResult struct {
	DisplayName string
	MinLat      float64
	MaxLat      float64
	MinLng      float64
	MaxLng      float64
	CenterLat   float64
	CenterLng   float64
	Slug        string
}

// Nominatim is a rate-limited client for the OSM Nominatim search endpoint.
// It is safe for concurrent use: requests are serialized so the 1 req/s policy
// holds even under parallel callers.
type Nominatim struct {
	baseURL   string
	userAgent string
	client    *http.Client

	mu          sync.Mutex
	lastRequest time.Time
}

// NewNominatim builds a Nominatim client with sane defaults.
func NewNominatim() *Nominatim {
	return &Nominatim{
		baseURL:   defaultBaseURL,
		userAgent: defaultUserAgent,
		client:    &http.Client{Timeout: 15 * time.Second},
	}
}

// nominatimResult mirrors the relevant subset of a Nominatim search result.
// boundingbox is encoded as an array of four strings:
// [min_lat, max_lat, min_lng, max_lng]. lat/lon are also strings.
type nominatimResult struct {
	DisplayName string   `json:"display_name"`
	Lat         string   `json:"lat"`
	Lon         string   `json:"lon"`
	BoundingBox []string `json:"boundingbox"`
}

// SearchCity resolves a city name to its bounding box and center via Nominatim.
// It blocks as needed to honor the 1 request/second rate limit.
func (n *Nominatim) SearchCity(ctx context.Context, name string) (*CitySearchResult, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return nil, errors.New("geocoding: name is required")
	}

	body, err := n.doSearch(ctx, trimmed)
	if err != nil {
		return nil, err
	}

	var results []nominatimResult
	if err := json.Unmarshal(body, &results); err != nil {
		return nil, fmt.Errorf("geocoding: decode response: %w", err)
	}
	if len(results) == 0 {
		return nil, ErrCityNotFound
	}

	r := results[0]
	if len(r.BoundingBox) != 4 {
		return nil, fmt.Errorf("geocoding: unexpected boundingbox length %d", len(r.BoundingBox))
	}

	minLat, err := strconv.ParseFloat(r.BoundingBox[0], 64)
	if err != nil {
		return nil, fmt.Errorf("geocoding: parse min_lat: %w", err)
	}
	maxLat, err := strconv.ParseFloat(r.BoundingBox[1], 64)
	if err != nil {
		return nil, fmt.Errorf("geocoding: parse max_lat: %w", err)
	}
	minLng, err := strconv.ParseFloat(r.BoundingBox[2], 64)
	if err != nil {
		return nil, fmt.Errorf("geocoding: parse min_lng: %w", err)
	}
	maxLng, err := strconv.ParseFloat(r.BoundingBox[3], 64)
	if err != nil {
		return nil, fmt.Errorf("geocoding: parse max_lng: %w", err)
	}
	centerLat, err := strconv.ParseFloat(r.Lat, 64)
	if err != nil {
		return nil, fmt.Errorf("geocoding: parse lat: %w", err)
	}
	centerLng, err := strconv.ParseFloat(r.Lon, 64)
	if err != nil {
		return nil, fmt.Errorf("geocoding: parse lon: %w", err)
	}

	return &CitySearchResult{
		DisplayName: r.DisplayName,
		MinLat:      minLat,
		MaxLat:      maxLat,
		MinLng:      minLng,
		MaxLng:      maxLng,
		CenterLat:   centerLat,
		CenterLng:   centerLng,
		Slug:        Slugify(trimmed),
	}, nil
}

// doSearch performs the rate-limited HTTP GET against Nominatim.
func (n *Nominatim) doSearch(ctx context.Context, name string) ([]byte, error) {
	// Serialize and throttle: hold the lock across the request so concurrent
	// callers cannot exceed one request per second.
	n.mu.Lock()
	defer n.mu.Unlock()

	if elapsed := time.Since(n.lastRequest); elapsed < minInterval {
		wait := minInterval - elapsed
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(wait):
		}
	}

	q := url.Values{}
	q.Set("q", name)
	q.Set("format", "json")
	q.Set("limit", "1")
	q.Set("addressdetails", "1")
	endpoint := n.baseURL + "?" + q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", n.userAgent)
	req.Header.Set("Accept", "application/json")

	resp, err := n.client.Do(req)
	n.lastRequest = time.Now()
	if err != nil {
		return nil, fmt.Errorf("geocoding: request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("geocoding: unexpected status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

// cyrillicToLatin maps Russian Cyrillic letters to a Latin transliteration.
// Soft/hard signs map to empty. "Махачкала" → "mahachkala".
var cyrillicToLatin = map[rune]string{
	'а': "a", 'б': "b", 'в': "v", 'г': "g", 'д': "d", 'е': "e", 'ё': "e",
	'ж': "zh", 'з': "z", 'и': "i", 'й': "y", 'к': "k", 'л': "l", 'м': "m",
	'н': "n", 'о': "o", 'п': "p", 'р': "r", 'с': "s", 'т': "t", 'у': "u",
	'ф': "f", 'х': "h", 'ц': "ts", 'ч': "ch", 'ш': "sh", 'щ': "sch",
	'ъ': "", 'ы': "y", 'ь': "", 'э': "e", 'ю': "yu", 'я': "ya",
}

// Slugify lowercases a name, transliterates Russian to Latin, and joins the
// remaining word characters with hyphens. "Махачкала" → "mahachkala".
func Slugify(name string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(strings.TrimSpace(name)) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == ' ' || r == '-' || r == '_':
			b.WriteByte('-')
		default:
			if latin, ok := cyrillicToLatin[r]; ok {
				b.WriteString(latin)
			}
			// Any other rune (punctuation, other scripts) is dropped.
		}
	}
	return collapseHyphens(b.String())
}

// collapseHyphens trims and squeezes runs of '-' into a single hyphen.
func collapseHyphens(s string) string {
	parts := strings.FieldsFunc(s, func(r rune) bool { return r == '-' })
	return strings.Join(parts, "-")
}
