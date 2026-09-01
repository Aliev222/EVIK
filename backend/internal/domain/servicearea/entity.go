package servicearea

import (
	"encoding/json"
	"math"
)

type ServiceArea struct {
	ID              string
	Name            string
	Slug            string
	MinLat          float64
	MinLng          float64
	MaxLat          float64
	MaxLng          float64
	CenterLat       float64
	CenterLng       float64
	RadiusKM        float64
	PrimaryRadiusKM float64
	IsActive        bool
	// BoundaryGeoJSON holds an optional GeoJSON polygon (Feature/FeatureCollection
	// or a plain Polygon) describing the real administrative boundary of the
	// city. When present, point-in-polygon tests are used instead of circles so
	// neighbouring cities do not overlap.
	BoundaryGeoJSON string
	// BoundaryBufferKM is the distance (km) by which the boundary polygon is
	// expanded for matching points just outside the exact boundary. Only used
	// when a polygon exists.
	BoundaryBufferKM float64
}

func (a ServiceArea) Contains(lat, lng float64) bool {
	if !a.IsActive {
		return false
	}
	if a.BoundaryGeoJSON != "" {
		return a.containsBoundary(lat, lng)
	}
	return a.ContainsWithRadius(lat, lng, a.RadiusKM)
}

func (a ServiceArea) ContainsWithRadius(lat, lng float64, radius float64) bool {
	if !a.IsActive {
		return false
	}
	return haversineKM(a.CenterLat, a.CenterLng, lat, lng) <= radius
}

// containsBoundary runs a point-in-polygon test over the stored GeoJSON
// boundary. Falls back to the primary circle if the polygon cannot be parsed.
func (a ServiceArea) containsBoundary(lat, lng float64) bool {
	polys, ok := parseBoundaryPolygons(a.BoundaryGeoJSON)
	if !ok {
		return a.ContainsWithRadius(lat, lng, a.PrimaryRadiusKM)
	}
	for _, poly := range polys {
		if pointInPolygon(lat, lng, poly) {
			return true
		}
	}
	return false
}


// MatchLevel describes how a point matched against a service area. Used to
// implement the strict priority: polygon > buffer > circle.
type MatchLevel int

const (
	MatchNone   MatchLevel = iota
	MatchCircle MatchLevel = 1
	MatchBuffer MatchLevel = 2
	MatchPolygon MatchLevel = 3
)

// Match returns how strongly the point belongs to this area. A point inside
// the exact polygon matches strongest; a point inside the boundary buffer
// matches medium; a point inside the old circle (only for areas with NO
// polygon) matches weakest. Areas with a polygon never fall back to their
// circle, so their circle is ignored.
func (a ServiceArea) Match(lat, lng float64) MatchLevel {
	if !a.IsActive {
		return MatchNone
	}
	if a.BoundaryGeoJSON != "" {
		if a.containsBoundary(lat, lng) {
			return MatchPolygon
		}
		if a.containsBuffer(lat, lng) {
			return MatchBuffer
		}
		return MatchNone
	}
	if a.ContainsWithRadius(lat, lng, a.RadiusKM) {
		return MatchCircle
	}
	return MatchNone
}

// containsBuffer tests the point against a buffer (expansion) around the
// stored boundary polygon. Falls back to a circle around the centroid when the
// polygon cannot be parsed.
func (a ServiceArea) containsBuffer(lat, lng float64) bool {
	polys, ok := parseBoundaryPolygons(a.BoundaryGeoJSON)
	if !ok {
		return false
	}
	buf := a.BoundaryBufferKM
	if buf <= 0 {
		buf = 7.0
	}
	for _, poly := range polys {
		if distToPolygonKM(lat, lng, poly) <= buf {
			return true
		}
	}
	return false
}

// distToPolygonKM computes the minimum great-circle distance from a point to a
// polygon ring using a fine sampled approximation of the polygon edges.
func distToPolygonKM(lat, lng float64, ring [][2]float64) float64 {
	n := len(ring)
	if n < 2 {
		return 1e9
	}
	if pointInPolygon(lat, lng, ring) {
		return 0
	}
	minD := 1e18
	for i := 0; i < n; i++ {
		a := ring[i]
		b := ring[(i+1)%n]
		d := pointToSegmentKM(lat, lng, a, b)
		if d < minD {
			minD = d
		}
	}
	return minD
}

// pointToSegmentKM returns the great-circle distance from a point to a segment.
func pointToSegmentKM(lat, lng float64, a, b [2]float64) float64 {
	// Sample the segment finely and take the minimum distance.
	const steps = 24
	minD := 1e18
	for i := 0; i <= steps; i++ {
		t := float64(i) / float64(steps)
		sLat := a[0] + (b[0]-a[0])*t
		sLng := a[1] + (b[1]-a[1])*t
		d := haversineKM(lat, lng, sLat, sLng)
		if d < minD {
			minD = d
		}
	}
	return minD
}

// ComputeBBox overwrites min/max lat/lng so the SQL bbox prefilter never
// excludes a point that the exact check would accept. If a polygon boundary
// exists, the bbox covers the polygon; otherwise it covers the larger of the
// two circles (RadiusKM / PrimaryRadiusKM).
func (a *ServiceArea) ComputeBBox() {
	if a.BoundaryGeoJSON != "" {
		if lat1, lng1, lat2, lng2, ok := boundaryBBox(a.BoundaryGeoJSON); ok {
			a.MinLat = lat1
			a.MinLng = lng1
			a.MaxLat = lat2
			a.MaxLng = lng2
			return
		}
	}

	radius := a.RadiusKM
	if a.PrimaryRadiusKM > radius {
		radius = a.PrimaryRadiusKM
	}

	const earthRadius = 6371.0
	angRad := radius / earthRadius
	dLat := angRad * 180 / math.Pi

	cosLat := math.Cos(a.CenterLat * math.Pi / 180)
	if cosLat < 0.01 {
		cosLat = 0.01
	}
	dLng := angRad / cosLat * 180 / math.Pi

	a.MinLat = a.CenterLat - dLat
	a.MaxLat = a.CenterLat + dLat
	a.MinLng = a.CenterLng - dLng
	a.MaxLng = a.CenterLng + dLng
}

func boundaryBBox(geoJSON string) (minLat, minLng, maxLat, maxLng float64, ok bool) {
	polys, o := parseBoundaryPolygons(geoJSON)
	if !o {
		return 0, 0, 0, 0, false
	}
	first := false
	for _, poly := range polys {
		for _, pt := range poly {
			if !first {
				minLat = pt[0]
				maxLat = pt[0]
				minLng = pt[1]
				maxLng = pt[1]
				first = true
			} else {
				if pt[0] < minLat {
					minLat = pt[0]
				}
				if pt[0] > maxLat {
					maxLat = pt[0]
				}
				if pt[1] < minLng {
					minLng = pt[1]
				}
				if pt[1] > maxLng {
					maxLng = pt[1]
				}
			}
		}
	}
	return minLat, minLng, maxLat, maxLng, first
}

// parseBoundaryPolygons extracts [][]Point rings from a GeoJSON object that may
// be a Feature, FeatureCollection, Polygon, or MultiPolygon. Returns the list of
// outer rings (lat,lng pairs in [lat,lng] order).
func parseBoundaryPolygons(geoJSON string) ([][][2]float64, bool) {
	var raw map[string]any
	if err := json.Unmarshal([]byte(geoJSON), &raw); err != nil {
		return nil, false
	}
	t, _ := raw["type"].(string)
	switch t {
	case "Feature":
		return parseGeometry(raw["geometry"])
	case "FeatureCollection":
		if feats, ok := raw["features"].([]any); ok {
			var all [][][2]float64
			for _, f := range feats {
				if fm, ok := f.(map[string]any); ok {
					if polys, ok := parseGeometry(fm["geometry"]); ok {
						all = append(all, polys...)
					}
				}
			}
			return all, len(all) > 0
		}
		return nil, false
	default:
		return parseGeometry(raw)
	}
}

func parseGeometry(g any) ([][][2]float64, bool) {
	gm, ok := g.(map[string]any)
	if !ok {
		return nil, false
	}
	t, _ := gm["type"].(string)
	switch t {
	case "Polygon":
		return parsePolygon(gm["coordinates"])
	case "MultiPolygon":
		if coords, ok := gm["coordinates"].([]any); ok {
			var all [][][2]float64
			for _, p := range coords {
				if polys, ok := parsePolygon(p); ok {
					all = append(all, polys...)
				}
			}
			return all, len(all) > 0
		}
	}
	return nil, false
}

func parsePolygon(c any) ([][][2]float64, bool) {
	rings, ok := c.([]any)
	if !ok || len(rings) == 0 {
		return nil, false
	}
	var out [][2]float64
	outer, ok := rings[0].([]any)
	if !ok {
		return nil, false
	}
	for _, pt := range outer {
		coord, ok := pt.([]any)
		if !ok || len(coord) < 2 {
			continue
		}
		lng, _ := toFloat(coord[0])
		lat, _ := toFloat(coord[1])
		out = append(out, [2]float64{lat, lng})
	}
	if len(out) < 3 {
		return nil, false
	}
	return [][][2]float64{out}, true
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case json.Number:
		f, err := n.Float64()
		return f, err == nil
	}
	return 0, false
}

// pointInPolygon implements the ray-casting algorithm on a ring of [lat,lng]
// points. Handles standard rings (not closed: last != first is fine).
func pointInPolygon(lat, lng float64, ring [][2]float64) bool {
	n := len(ring)
	if n < 3 {
		return false
	}
	inside := false
	j := n - 1
	for i := 0; i < n; i++ {
		yi := ring[i][0]
		xi := ring[i][1]
		yj := ring[j][0]
		xj := ring[j][1]
		if (yi > lat) != (yj > lat) {
			if lng < (xj-xi)*(lat-yi)/(yj-yi)+xi {
				inside = !inside
			}
		}
		j = i
	}
	return inside
}

func HaversineDistance(lat1, lng1, lat2, lng2 float64) float64 {
	return haversineKM(lat1, lng1, lat2, lng2)
}

func haversineKM(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371.0
	dLat := (lat2 - lat1) * math.Pi / 180
	dLng := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLng/2)*math.Sin(dLng/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
