package servicearea

type ServiceArea struct {
	ID       string
	Name     string
	Slug     string
	MinLat   float64
	MinLng   float64
	MaxLat   float64
	MaxLng   float64
	IsActive bool
}

func (a ServiceArea) Contains(lat, lng float64) bool {
	return a.IsActive &&
		lat >= a.MinLat && lat <= a.MaxLat &&
		lng >= a.MinLng && lng <= a.MaxLng
}
