package servicearea

import (
	"encoding/json"
	"testing"
)

func TestPointInPolygon_Inside(t *testing.T) {
	// A small axis-aligned square ring (lat,lng). Not closed.
	ring := [][2]float64{{0, 0}, {0, 10}, {10, 10}, {10, 0}}
	if !pointInPolygon(5, 5, ring) {
		t.Fatal("expected (5,5) inside square")
	}
}

func TestPointInPolygon_Outside(t *testing.T) {
	ring := [][2]float64{{0, 0}, {0, 10}, {10, 10}, {10, 0}}
	if pointInPolygon(15, 5, ring) {
		t.Fatal("expected (15,5) outside square")
	}
}

func polygonFixture(lat0, lng0, lat1, lng1 float64) string {
	// Return a GeoJSON Polygon whose bbox is [lat0..lat1] x [lng0..lng1],
	// a simple axis-aligned rectangle. Coordinates order is [lng, lat].
	poly := map[string]any{
		"type": "Polygon",
		"coordinates": []any{
			[]any{
				[]any{lng0, lat0},
				[]any{lng1, lat0},
				[]any{lng1, lat1},
				[]any{lng0, lat1},
				[]any{lng0, lat0},
			},
		},
	}
	b, _ := json.Marshal(poly)
	return string(b)
}

// TestPolygonBeatsCircleAcrossAreas simulates the dispatcher CheckPoint
// priority: a point INSIDE area A's polygon AND inside area B's circle must be
// assigned to A (polygon), regardless of B being a circle.
func TestPolygonBeatsCircle(t *testing.T) {
	// A has a polygon around center (0,0). B has a wide circle radius 200km
	// centered far away but still reaching the point.
	a := ServiceArea{
		ID:              "A",
		Name:            "A",
		IsActive:        true,
		BoundaryGeoJSON: polygonFixture(-1, -1, 1, 1),
		BoundaryBufferKM: 7,
	}
	// B is centered at (0, 1.0) with radius 200km → its circle covers point (0,0)
	// (0,0) is ~111km from B center, inside a 200km circle.
	b := ServiceArea{
		ID:        "B",
		Name:      "B",
		IsActive:  true,
		CenterLat: 0,
		CenterLng: 1.0,
		RadiusKM:  200,
	}

	if a.Match(0, 0) != MatchPolygon {
		t.Fatal("A should match point as polygon")
	}
	if b.Match(0, 0) != MatchCircle {
		t.Fatal("point (0,0) should also be inside B circle")
	}

	// Priority resolution: polygon A must win over circle B.
	if a.Match(0, 0) <= b.Match(0, 0) {
		t.Fatal("polygon match must outrank circle match")
	}
}

func TestBufferMatch(t *testing.T) {
	// Square centered at (0,0) with corners ±1°. A point just outside the
	// polygon but within the buffer (7km) must match as Buffer.
	a := ServiceArea{
		ID:               "A",
		Name:             "A",
		IsActive:         true,
		BoundaryGeoJSON:  polygonFixture(-1, -1, 1, 1),
		BoundaryBufferKM: 7,
	}
	// Point at (1.03, 0) → ~3.3km north of the top edge (lat=1). Within 7km.
	if a.Match(1.04, 0) != MatchBuffer {
		t.Fatalf("expected buffer match, got %d", a.Match(1.04, 0))
	}
	// Point at (1.3, 0) → ~33km north, outside buffer and polygon.
	if a.Match(1.3, 0) != MatchNone {
		t.Fatalf("expected no match far away, got %d", a.Match(1.3, 0))
	}
}

func TestCircleFallbackForNoPolygon(t *testing.T) {
	a := ServiceArea{
		ID:        "A",
		Name:      "A",
		IsActive:  true,
		CenterLat: 0,
		CenterLng: 0,
		RadiusKM:  50,
	}
	if a.Match(0.2, 0) != MatchCircle {
		t.Fatalf("expected circle match, got %d", a.Match(0.2, 0))
	}
	// Far away should be none.
	if a.Match(5, 0) != MatchNone {
		t.Fatalf("expected none, got %d", a.Match(5, 0))
	}
}

func TestPolygonAreaDoesNotFallbackToCircle(t *testing.T) {
	// Area with a small polygon must NOT use a huge circle even if configured.
	a := ServiceArea{
		ID:               "A",
		Name:             "A",
		IsActive:         true,
		BoundaryGeoJSON:  polygonFixture(-0.01, -0.01, 0.01, 0.01),
		BoundaryBufferKM: 1,
		RadiusKM:         500, // huge imaginary circle
	}
	// Point ~10km away from a tiny polygon, well within the 500km circle, but
	// NOT within polygon or buffer → must be MatchNone (no circle fallback).
	if m := a.Match(0.1, 0); m != MatchNone {
		t.Fatalf("polygon area must not fall back to circle, got %d", m)
	}
}

func TestInactiveAreaNoMatch(t *testing.T) {
	a := ServiceArea{
		ID:               "A",
		IsActive:         false,
		BoundaryGeoJSON:  polygonFixture(-1, -1, 1, 1),
		BoundaryBufferKM: 7,
		RadiusKM:         50,
	}
	if a.Match(0, 0) != MatchNone {
		t.Fatal("inactive area should never match")
	}
}
