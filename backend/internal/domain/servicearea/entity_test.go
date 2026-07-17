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
