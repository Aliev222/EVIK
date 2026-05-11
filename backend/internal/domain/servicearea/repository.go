package servicearea

import "context"

type Repository interface {
	CheckPoint(ctx context.Context, lat, lng float64) (*ServiceArea, bool, error)
}
