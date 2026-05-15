package redis

import (
	"context"
	"strconv"
	"time"

	"evik/backend/internal/domain/location"
	"github.com/redis/go-redis/v9"
)

type LocationStore struct {
	client *redis.Client
}

func NewLocationStore(client *redis.Client) *LocationStore {
	return &LocationStore{client: client}
}

func (s *LocationStore) SaveLocation(ctx context.Context, driverID string, loc location.Location) error {
	if err := s.client.GeoAdd(ctx, "drivers:geo", &redis.GeoLocation{
		Name:      driverID,
		Latitude:  loc.Lat,
		Longitude: loc.Lng,
	}).Err(); err != nil {
		return err
	}
	return s.client.Set(ctx, "drivers:location:updated_at:"+driverID, loc.UpdatedAt.Unix(), 24*time.Hour).Err()
}

func (s *LocationStore) GetNearbyDrivers(ctx context.Context, pickup location.Location, radiusKM float64, limit int) ([]location.DriverLocation, error) {
	res, err := s.client.GeoRadius(ctx, "drivers:geo", pickup.Lng, pickup.Lat, &redis.GeoRadiusQuery{
		Radius:    radiusKM,
		Unit:      "km",
		WithCoord: true,
		WithDist:  true,
		Count:     limit,
		Sort:      "ASC",
	}).Result()
	if err != nil {
		return nil, err
	}

	out := make([]location.DriverLocation, 0, len(res))
	for _, item := range res {
		updatedAt := time.Now().UTC()
		ts, err := s.client.Get(ctx, "drivers:location:updated_at:"+item.Name).Result()
		if err == nil {
			if unix, parseErr := strconv.ParseInt(ts, 10, 64); parseErr == nil {
				updatedAt = time.Unix(unix, 0).UTC()
			}
		}

		out = append(out, location.DriverLocation{
			DriverID: item.Name,
			Location: location.Location{
				Lat:       item.Latitude,
				Lng:       item.Longitude,
				UpdatedAt: updatedAt,
			},
			DistanceKM: item.Dist,
		})
	}
	return out, nil
}

func (s *LocationStore) GetLastLocation(ctx context.Context, driverID string) (*location.Location, error) {
	coords, err := s.client.GeoPos(ctx, "drivers:geo", driverID).Result()
	if err != nil {
		return nil, err
	}
	if len(coords) == 0 || coords[0] == nil {
		return nil, location.ErrLocationNotFound
	}

	updatedAt := time.Now().UTC()
	ts, err := s.client.Get(ctx, "drivers:location:updated_at:"+driverID).Result()
	if err == nil {
		if unix, parseErr := strconv.ParseInt(ts, 10, 64); parseErr == nil {
			updatedAt = time.Unix(unix, 0).UTC()
		}
	}

	return &location.Location{
		Lat:       coords[0].Latitude,
		Lng:       coords[0].Longitude,
		UpdatedAt: updatedAt,
	}, nil
}

func (s *LocationStore) RemoveDriver(ctx context.Context, driverID string) error {
	if err := s.client.ZRem(ctx, "drivers:geo", driverID).Err(); err != nil {
		return err
	}
	return s.client.Del(ctx, "drivers:location:updated_at:"+driverID).Err()
}
