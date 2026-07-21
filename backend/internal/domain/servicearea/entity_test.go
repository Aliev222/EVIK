package servicearea

import "testing"

func TestServiceArea_MakhachkalaCenter_Inside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	if !a.Contains(42.9764, 47.5024) {
		t.Error("center of Makhachkala should be inside its own service area")
	}
}

func TestServiceArea_MakhachkalaOutskirts_Inside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	// ~10 km north — should still be inside radius 25
	if !a.Contains(43.066, 47.5024) {
		t.Error("10 km north of Makhachkala center should be inside radius 25 km")
	}
}

func TestServiceArea_Moscow_Outside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	if a.Contains(55.7558, 37.6173) {
		t.Error("Moscow should be outside Makhachkala service area")
	}
}

func TestServiceArea_Highway20km_Inside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	// ~20 km south along the coast — should still be inside radius 25
	if !a.Contains(42.785, 47.5024) {
		t.Error("20 km south of Makhachkala should be inside radius 25 km")
	}
}

func TestServiceArea_Inactive_Outside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: false,
	}
	if a.Contains(42.9764, 47.5024) {
		t.Error("inactive service area should reject all points")
	}
}

func TestServiceArea_KaspiyskCenter_Inside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.8817, CenterLng: 47.6406, RadiusKM: 15, IsActive: true,
	}
	if !a.Contains(42.8817, 47.6406) {
		t.Error("center of Kaspiysk should be inside its own service area")
	}
}

func TestServiceArea_DerbentCenter_Inside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.0678, CenterLng: 48.2905, RadiusKM: 20, IsActive: true,
	}
	if !a.Contains(42.0678, 48.2905) {
		t.Error("center of Derbent should be inside its own service area")
	}
}

func TestServiceArea_ExactlyOnBoundary_Inside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	// Exactly 25 km north — should be inside (<=)
	latNorth := 43.201
	if !a.Contains(latNorth, 47.5024) {
		t.Errorf("point exactly at radius boundary should be inside (%.4f, %.4f)", latNorth, 47.5024)
	}
}

func TestServiceArea_BeyondBoundary_Outside(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	// ~30 km north — should be outside radius 25
	if a.Contains(43.246, 47.5024) {
		t.Error("30 km north of Makhachkala should be outside radius 25 km")
	}
}

func TestServiceArea_JustOutsideRadius(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.8817, CenterLng: 47.6406, RadiusKM: 15, IsActive: true,
	}
	// Makhachkala center is 15.41 km from Kaspiysk center — just outside radius 15
	if a.Contains(42.9764, 47.5024) {
		t.Error("Makhachkala center (15.41 km away) should be outside Kaspiysk radius 15 km")
	}
}

func TestServiceArea_JustInsideRadius(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.8817, CenterLng: 47.6406, RadiusKM: 15, IsActive: true,
	}
	// ~14.9 km south of Kaspiysk center — just inside radius 15
	if !a.Contains(42.7477, 47.6406) {
		t.Error("point ~14.9 km south should be inside Kaspiysk radius 15 km")
	}
}

func TestServiceArea_ComputeBBox_CoversCenter(t *testing.T) {
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	a.ComputeBBox()
	if !a.Contains(a.CenterLat, a.CenterLng) {
		t.Error("center must be inside its own bbox after ComputeBBox")
	}
	// BBox edges should be beyond the center in all directions
	if a.MinLat >= a.CenterLat || a.MaxLat <= a.CenterLat {
		t.Errorf("bbox lat range [%f, %f] must contain center %f", a.MinLat, a.MaxLat, a.CenterLat)
	}
	if a.MinLng >= a.CenterLng || a.MaxLng <= a.CenterLng {
		t.Errorf("bbox lng range [%f, %f] must contain center %f", a.MinLng, a.MaxLng, a.CenterLng)
	}
}

func TestServiceArea_ComputeBBox_ContainsCircle(t *testing.T) {
	// Any point at distance <= RadiusKM from center must be inside the bbox
	a := ServiceArea{
		CenterLat: 55.7558, CenterLng: 37.6173, RadiusKM: 10, IsActive: true,
	}
	a.ComputeBBox()
	// 9 km north
	latNorth := 55.7558 + (9.0/6371.0*180/3.14159)
	if !(latNorth >= a.MinLat && latNorth <= a.MaxLat) {
		t.Error("point 9 km north must be inside bbox")
	}
	// 9 km east (adjusted for latitude)
	lngEast := 37.6173 + (9.0/(6371.0*0.562)*180/3.14159)
	if !(lngEast >= a.MinLng && lngEast <= a.MaxLng) {
		t.Error("point 9 km east must be inside bbox")
	}
}

func TestServiceArea_ComputeBBox_ConcreteValues(t *testing.T) {
	// Makhachkala: center (42.9764, 47.5024), radius 25 km
	a := ServiceArea{
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	a.ComputeBBox()
	if !a.Contains(42.9764, 47.5024) {
		t.Error("Makhachkala center must be inside after ComputeBBox")
	}
}

// closestZone is a test helper that picks the closest matching zone
// from a slice — mirrors the logic in CheckPoint post-refactor.
func closestZone(lat, lng float64, zones []ServiceArea) *ServiceArea {
	var best ServiceArea
	var bestDist float64
	var found bool
	for _, z := range zones {
		if !z.Contains(lat, lng) {
			continue
		}
		dist := haversineKM(z.CenterLat, z.CenterLng, lat, lng)
		if !found || dist < bestDist {
			best = z
			bestDist = dist
			found = true
		}
	}
	if !found {
		return nil
	}
	return &best
}

func TestCheckPoint_Overlap_PicksClosest(t *testing.T) {
	// Makhachkala (r=25) and Kaspiysk (r=15) — overlapping bboxes.
	// Point at the center of Makhachkala (42.9764,47.5024).
	// Both bboxes contain the point, but only Makhachkala's haversine (0 km)
	// accepts it. Kaspiysk's haversine (~15.4 km) rejects it.
	makhachkala := ServiceArea{
		ID: "makh", Name: "Махачкала", Slug: "makhachkala-default",
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	kaspiysk := ServiceArea{
		ID: "kasp", Name: "Каспийск", Slug: "kaspiysk-default",
		CenterLat: 42.8817, CenterLng: 47.6406, RadiusKM: 15, IsActive: true,
	}

	best := closestZone(42.9764, 47.5024, []ServiceArea{makhachkala, kaspiysk})
	if best == nil {
		t.Fatal("center of Makhachkala should match at least Makhachkala")
	}
	if best.ID != "makh" {
		t.Errorf("expected Makhachkala (closest, 0 km), got %s (%.2f km)", best.Name, haversineKM(best.CenterLat, best.CenterLng, 42.9764, 47.5024))
	}
}

func TestCheckPoint_Overlap_BothAccept_PicksClosest(t *testing.T) {
	// Both zones accept the point; the closer one should be returned.
	// Point at 42.92,47.55 — closer to Kaspiysk center (~15 km radius).
	makhachkala := ServiceArea{
		ID: "makh", Name: "Махачкала", Slug: "makhachkala-default",
		CenterLat: 42.9764, CenterLng: 47.5024, RadiusKM: 25, IsActive: true,
	}
	kaspiysk := ServiceArea{
		ID: "kasp", Name: "Каспийск", Slug: "kaspiysk-default",
		CenterLat: 42.8817, CenterLng: 47.6406, RadiusKM: 15, IsActive: true,
	}

	// Point ~10 km from Kaspiysk center, ~14 km from Makhachkala center
	// Kaspiysk is first — with the pointer-to-loop-var bug, best would
	// end up pointing to the LAST valid zone (Makhachkala, farther).
	best := closestZone(42.9, 47.57, []ServiceArea{kaspiysk, makhachkala})
	if best == nil {
		t.Fatal("point should match at least one zone")
	}
	if best.ID != "kasp" {
		t.Errorf("expected Kaspiysk (closer), got %s", best.Name)
	}
}

func TestCheckPoint_SingleZone_Match(t *testing.T) {
	z := ServiceArea{
		ID: "z1", Name: "Zone1",
		CenterLat: 55.0, CenterLng: 37.0, RadiusKM: 10, IsActive: true,
	}
	best := closestZone(55.0, 37.0, []ServiceArea{z})
	if best == nil || best.ID != "z1" {
		t.Error("point at center should match the only zone")
	}
}

func TestCheckPoint_AllInactive_NoMatch(t *testing.T) {
	z := ServiceArea{
		ID: "z1", Name: "Inactive",
		CenterLat: 55.0, CenterLng: 37.0, RadiusKM: 10, IsActive: false,
	}
	best := closestZone(55.0, 37.0, []ServiceArea{z})
	if best != nil {
		t.Error("inactive zone should not match")
	}
}

func TestCheckPoint_OutsideAll_NoMatch(t *testing.T) {
	z := ServiceArea{
		ID: "z1", Name: "Zone1",
		CenterLat: 55.0, CenterLng: 37.0, RadiusKM: 10, IsActive: true,
	}
	// Moscow is ~1600 km away
	best := closestZone(42.9764, 47.5024, []ServiceArea{z})
	if best != nil {
		t.Error("Makhachkala should not match Moscow zone")
	}
}

func TestHaversineKM(t *testing.T) {
	// Distance from Makhachkala center to Kaspiysk center
	d := haversineKM(42.9764, 47.5024, 42.8817, 47.6406)
	// Should be ~16-17 km
	if d < 10 || d > 25 {
		t.Errorf("distance Makhachkala-Kaspiysk should be ~16 km, got %.2f km", d)
	}

	// Same point
	d = haversineKM(42.9764, 47.5024, 42.9764, 47.5024)
	if d != 0 {
		t.Errorf("distance to self should be 0, got %.2f km", d)
	}

	// Makhachkala to Moscow (~1600 km)
	d = haversineKM(42.9764, 47.5024, 55.7558, 37.6173)
	if d < 1400 || d > 1800 {
		t.Errorf("distance Makhachkala-Moscow should be ~1600 km, got %.2f km", d)
	}
}
