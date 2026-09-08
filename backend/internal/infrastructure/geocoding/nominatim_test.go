package geocoding

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSearchDoesNotRequestPolygonGeometry(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/search" {
			t.Fatalf("path = %q, want /search", r.URL.Path)
		}
		if got := r.URL.Query().Get("polygon_geojson"); got != "" {
			t.Fatalf("polygon_geojson = %q, want omitted for autocomplete", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"display_name":"Махачкала","lat":"42.984","lon":"47.505","boundingbox":["42.9","43.0","47.4","47.6"],"osm_id":1,"type":"city"}]`))
	}))
	defer server.Close()

	client := NewNominatim(server.URL)
	results, err := client.Search(context.Background(), "Махачкала", 1)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 1 || results[0].DisplayName != "Махачкала" {
		t.Fatalf("results = %#v", results)
	}
}
