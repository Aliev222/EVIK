package servicearea

import "math"

type ServiceArea struct {
	ID       string
	Name     string
	Slug     string
	MinLat   float64
	MinLng   float64
	MaxLat   float64
	MaxLng   float64
	CenterLat float64
	CenterLng float64
	RadiusKM float64
	IsActive bool
}

func (a ServiceArea) Contains(lat, lng float64) bool {
	if !a.IsActive {
		return false
	}
	return haversineKM(a.CenterLat, a.CenterLng, lat, lng) <= a.RadiusKM
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
