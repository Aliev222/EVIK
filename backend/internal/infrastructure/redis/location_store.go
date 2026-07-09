package redis

import (
	"context"
	"errors"
	"fmt"
	"log"
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

func (s *LocationStore) GetLocations(ctx context.Context, driverIDs []string) (map[string]*location.Location, error) {
	if len(driverIDs) == 0 {
		return map[string]*location.Location{}, nil
	}
	coords, err := s.client.GeoPos(ctx, "drivers:geo", driverIDs...).Result()
	if err != nil {
		return nil, err
	}

	pipe := s.client.Pipeline()
	cmds := make([]*redis.StringCmd, len(driverIDs))
	for i, id := range driverIDs {
		cmds[i] = pipe.Get(ctx, "drivers:location:updated_at:"+id)
	}
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
		log.Printf("ERROR: Redis pipeline failed: %v", err)
	}

	result := make(map[string]*location.Location, len(driverIDs))
	for i, id := range driverIDs {
		if i >= len(coords) || coords[i] == nil {
			continue
		}
		updatedAt := time.Now().UTC()
		if ts, cmdErr := cmds[i].Result(); cmdErr == nil {
			if unix, parseErr := strconv.ParseInt(ts, 10, 64); parseErr == nil {
				updatedAt = time.Unix(unix, 0).UTC()
			}
		}
		result[id] = &location.Location{
			Lat:       coords[i].Latitude,
			Lng:       coords[i].Longitude,
			UpdatedAt: updatedAt,
		}
	}
	return result, nil
}

func (s *LocationStore) GetLastLocations(ctx context.Context, driverIDs []string) (map[string]*location.Location, error) {
	return s.GetLocations(ctx, driverIDs)
}

func (s *LocationStore) RemoveDriver(ctx context.Context, driverID string) error {
	if err := s.client.ZRem(ctx, "drivers:geo", driverID).Err(); err != nil {
		return err
	}
	return s.client.Del(ctx, "drivers:location:updated_at:"+driverID).Err()
}

// GetDriverIDsInBBox returns IDs of all drivers whose last known position
// falls within the given bounding box. Fetches all geo members then filters
// in Go — safe for the fleet sizes we operate at.
func (s *LocationStore) GetDriverIDsInBBox(ctx context.Context, minLat, minLng, maxLat, maxLng float64) ([]string, error) {
	ids, err := s.client.ZRange(ctx, "drivers:geo", 0, -1).Result()
	if err != nil || len(ids) == 0 {
		return nil, err
	}
	coords, err := s.client.GeoPos(ctx, "drivers:geo", ids...).Result()
	if err != nil {
		return nil, err
	}
	result := make([]string, 0, len(ids))
	for i, pos := range coords {
		if pos == nil {
			continue
		}
		if pos.Latitude >= minLat && pos.Latitude <= maxLat &&
			pos.Longitude >= minLng && pos.Longitude <= maxLng {
			result = append(result, ids[i])
		}
	}
	return result, nil
}

func (s *LocationStore) SetDriverCity(ctx context.Context, driverID, cityID string) error {
	return s.client.Set(ctx, "driver:"+driverID+":city_id", cityID, 24*time.Hour).Err()
}

func (s *LocationStore) GetDriverCity(ctx context.Context, driverID string) (string, error) {
	return s.client.Get(ctx, "driver:"+driverID+":city_id").Result()
}

func (s *LocationStore) SetLastCity(ctx context.Context, driverID, cityID string) error {
	const ttl = 2 * time.Hour
	pipe := s.client.Pipeline()
	pipe.Set(ctx, "driver:"+driverID+":last_city_id", cityID, ttl)
	pipe.Set(ctx, "driver:"+driverID+":last_city_at", time.Now().UTC().Unix(), ttl)
	_, err := pipe.Exec(ctx)
	return err
}

func (s *LocationStore) GetLastCity(ctx context.Context, driverID string) (string, time.Time, error) {
	pipe := s.client.Pipeline()
	cityCmd := pipe.Get(ctx, "driver:"+driverID+":last_city_id")
	atCmd := pipe.Get(ctx, "driver:"+driverID+":last_city_at")
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
		log.Printf("ERROR: Redis pipeline failed: %v", err)
	}

	cityID, err := cityCmd.Result()
	if err != nil {
		return "", time.Time{}, err
	}
	atStr, err := atCmd.Result()
	if errors.Is(err, redis.Nil) {
		return cityID, time.Now().UTC(), nil
	}
	if err != nil {
		return cityID, time.Now().UTC(), fmt.Errorf("location_store get last_city_at for driver %s: %w", driverID, err)
	}
	unix, err := strconv.ParseInt(atStr, 10, 64)
	if err != nil {
		return cityID, time.Now().UTC(), nil
	}
	return cityID, time.Unix(unix, 0).UTC(), nil
}

func (s *LocationStore) ClearLastCity(ctx context.Context, driverID string) error {
	return s.client.Del(ctx, "driver:"+driverID+":last_city_id", "driver:"+driverID+":last_city_at").Err()
}
