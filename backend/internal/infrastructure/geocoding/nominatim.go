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
	defaultBaseURL   = "https://nominatim.openstreetmap.org"
	defaultUserAgent = "AvroApp/1.0 (support@avro.app)"
	// minInterval enforces the Nominatim "max 1 request per second" policy.
	minInterval = time.Second
)

// ErrCityNotFound is returned when Nominatim has no result for the query.
var ErrCityNotFound = errors.New("geocoding: city not found")

// ErrReverseNotFound is returned when Nominatim has no address for the point.
var ErrReverseNotFound = errors.New("geocoding: address not found")

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
	OSMID       string
	Type        string
}

// Nominatim is a rate-limited client for the OSM Nominatim search/reverse
// endpoints. It is safe for concurrent use: requests are serialized so the
// 1 req/s policy holds even under parallel callers.
type Nominatim struct {
	baseURL   string
	userAgent string
	client    *http.Client

	mu          sync.Mutex
	lastRequest time.Time
}

// ReverseResult is the normalized reverse-geocoding result for a coordinate.
type ReverseResult struct {
	DisplayName string
}

// NewNominatim builds a Nominatim client. An empty baseURL falls back to the
// public OSM instance. The caller controls the base URL so deployments can
// point at a self-hosted Nominatim without hardcoding values.
func NewNominatim(baseURL string) *Nominatim {
	if baseURL == "" {
		baseURL = defaultBaseURL
	}
	return &Nominatim{
		baseURL:   strings.TrimRight(baseURL, "/"),
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
	OsmID       int64    `json:"osm_id"`
	Type        string   `json:"type"`
}

// SearchCity resolves a city name to its bounding box and center via Nominatim.
// It blocks as needed to honor the 1 request/second rate limit.
func (n *Nominatim) SearchCity(ctx context.Context, name string) (*CitySearchResult, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return nil, errors.New("geocoding: name is required")
	}

	body, err := n.doSearch(ctx, trimmed, 1)
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

// Search resolves a partial city name into up to limit autocomplete suggestions.
// Queries shorter than 3 runes return an empty slice without hitting Nominatim.
// It blocks as needed to honor the 1 request/second rate limit.
func (n *Nominatim) Search(ctx context.Context, query string, limit int) ([]CitySearchResult, error) {
	trimmed := strings.TrimSpace(query)
	if len([]rune(trimmed)) < 3 {
		return []CitySearchResult{}, nil
	}
	if limit <= 0 || limit > 5 {
		limit = 5
	}

	body, err := n.doSearch(ctx, trimmed, limit)
	if err != nil {
		return nil, err
	}

	var results []nominatimResult
	if err := json.Unmarshal(body, &results); err != nil {
		return nil, fmt.Errorf("geocoding: decode response: %w", err)
	}

	out := make([]CitySearchResult, 0, len(results))
	for _, r := range results {
		if len(r.BoundingBox) != 4 {
			continue
		}
		minLat, err1 := strconv.ParseFloat(r.BoundingBox[0], 64)
		maxLat, err2 := strconv.ParseFloat(r.BoundingBox[1], 64)
		minLng, err3 := strconv.ParseFloat(r.BoundingBox[2], 64)
		maxLng, err4 := strconv.ParseFloat(r.BoundingBox[3], 64)
		centerLat, err5 := strconv.ParseFloat(r.Lat, 64)
		centerLng, err6 := strconv.ParseFloat(r.Lon, 64)
		if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil || err6 != nil {
			continue
		}
		out = append(out, CitySearchResult{
			DisplayName: r.DisplayName,
			MinLat:      minLat,
			MaxLat:      maxLat,
			MinLng:      minLng,
			MaxLng:      maxLng,
			CenterLat:   centerLat,
			CenterLng:   centerLng,
			Slug:        Slugify(r.DisplayName),
			OSMID:       strconv.FormatInt(r.OsmID, 10),
			Type:        r.Type,
		})
	}
	return out, nil
}

// doSearch performs the rate-limited HTTP GET against Nominatim.
func (n *Nominatim) doSearch(ctx context.Context, name string, limit int) ([]byte, error) {
	release, err := n.throttleAndLock(ctx)
	if err != nil {
		return nil, err
	}
	defer release()

	q := url.Values{}
	q.Set("q", name)
	q.Set("format", "json")
	q.Set("limit", strconv.Itoa(limit))
	q.Set("addressdetails", "1")
	endpoint := n.baseURL + "/search?" + q.Encode()

	return n.get(ctx, endpoint)
}

// Reverse resolves a latitude/longitude point into a human-readable address via
// the Nominatim /reverse endpoint. It blocks as needed to honor the 1
// request/second policy and sends the same identifying User-Agent as search.
func (n *Nominatim) Reverse(ctx context.Context, lat, lng float64) (*ReverseResult, error) {
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return nil, errors.New("geocoding: invalid coordinates")
	}

	release, err := n.throttleAndLock(ctx)
	if err != nil {
		return nil, err
	}
	defer release()

	q := url.Values{}
	q.Set("lat", strconv.FormatFloat(lat, 'f', -1, 64))
	q.Set("lon", strconv.FormatFloat(lng, 'f', -1, 64))
	q.Set("format", "jsonv2")
	endpoint := n.baseURL + "/reverse?" + q.Encode()

	body, err := n.get(ctx, endpoint)
	if err != nil {
		return nil, err
	}

	var res struct {
		DisplayName string `json:"display_name"`
		Error       string `json:"error"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return nil, fmt.Errorf("geocoding: decode response: %w", err)
	}
	if strings.TrimSpace(res.Error) != "" {
		// Nominatim returns {"error": ...} when a point has no address
		// (e.g. open sea).
		return nil, fmt.Errorf("geocoding: reverse lookup failed: %s", res.Error)
	}
	if strings.TrimSpace(res.DisplayName) == "" {
		return nil, ErrReverseNotFound
	}
	return &ReverseResult{DisplayName: strings.TrimSpace(res.DisplayName)}, nil
}

// throttleAndLock serializes requests so callers cannot exceed the Nominatim
// policy of one request per second. The returned func MUST be released (defer)
// once the HTTP request completes so the timestamp is updated under the lock.
func (n *Nominatim) throttleAndLock(ctx context.Context) (func(), error) {
	n.mu.Lock()
	if elapsed := time.Since(n.lastRequest); elapsed < minInterval {
		wait := minInterval - elapsed
		select {
		case <-ctx.Done():
			n.mu.Unlock()
			return nil, ctx.Err()
		case <-time.After(wait):
		}
	}
	return n.mu.Unlock, nil
}

// get performs the authenticated-agnostic Nominatim request and returns the
// raw body. Callers must already hold the throttle lock.
func (n *Nominatim) get(ctx context.Context, endpoint string) ([]byte, error) {
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
