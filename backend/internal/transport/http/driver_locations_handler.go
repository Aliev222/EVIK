package http

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	servicearea "evik/backend/internal/domain/servicearea"
)

// driverOfflineThreshold is how stale a location must be before a driver is
// reported as "offline" regardless of their stored status.
const driverOfflineThreshold = 5 * time.Minute

// DriverProfileLister lists drivers enriched with user/vehicle profile data.
type DriverProfileLister interface {
	ListAllWithProfile(ctx context.Context, limit int) ([]*driverdomain.DriverProfile, error)
}

// DriverLocationReader resolves a driver's last known coordinate from Redis.
type DriverLocationReader interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
	GetLastLocations(ctx context.Context, driverIDs []string) (map[string]*locationdomain.Location, error)
}

// CityLookup resolves a service area (city) bbox by id, for map filtering.
type CityLookup interface {
	GetByID(ctx context.Context, id string) (*servicearea.ServiceArea, error)
}

// DriverLocationsHandler powers the admin live driver map.
type DriverLocationsHandler struct {
	drivers   DriverProfileLister
	locations DriverLocationReader
	cities    CityLookup
}

func NewDriverLocationsHandler(drivers DriverProfileLister, locations DriverLocationReader, cities CityLookup) *DriverLocationsHandler {
	return &DriverLocationsHandler{drivers: drivers, locations: locations, cities: cities}
}

type driverLocationResponse struct {
	DriverID     string  `json:"driver_id"`
	FullName     string  `json:"full_name"`
	Phone        string  `json:"phone"`
	AvatarURL    string  `json:"avatar_url"`
	VehiclePlate string  `json:"vehicle_plate"`
	Status       string  `json:"status"`
	Lat          float64 `json:"lat"`
	Lng          float64 `json:"lng"`
	LastSeenAt   string  `json:"last_seen_at"`
}

// @Summary      List driver locations (admin)
// @Description  Returns live driver locations for the admin map. Can be filtered by city and status.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        city_id  query  string  false  "Filter by city ID"
// @Param        status   query  string  false  "Filter by status"  Enums(online,offline,busy)
// @Success      200  {object}  []driverLocationResponse  "driver locations"
// @Failure      400  {object}  ErrorResponse  "invalid params"
// @Failure      404  {object}  ErrorResponse  "city not found"
// @Router       /admin/drivers/locations [get]
func (h *DriverLocationsHandler) List(w http.ResponseWriter, r *http.Request) {
	cityID := strings.TrimSpace(r.URL.Query().Get("city_id"))
	statusFilter := strings.TrimSpace(r.URL.Query().Get("status"))

	var bounds *servicearea.ServiceArea
	if cityID != "" {
		area, err := h.cities.GetByID(r.Context(), cityID)
		if err != nil {
			if errors.Is(err, servicearea.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "city not found"})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		bounds = area
	}

	drivers, err := h.drivers.ListAllWithProfile(r.Context(), 500)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	driverIDs := make([]string, len(drivers))
	for i, d := range drivers {
		driverIDs[i] = d.ID
	}
	locMap, err := h.locations.GetLastLocations(r.Context(), driverIDs)
	if err != nil {
		log.Printf("ERROR: batch get locations: %v", err)
	}

	now := time.Now().UTC()
	out := make([]driverLocationResponse, 0, len(drivers))
	for _, d := range drivers {
		loc, ok := locMap[d.ID]
		if !ok {
			continue
		}

		if bounds != nil && !withinCityBounds(loc.Lat, loc.Lng, bounds) {
			continue
		}

		status := string(d.Status)
		if now.Sub(loc.UpdatedAt) > driverOfflineThreshold {
			status = string(driverdomain.StatusOffline)
		}
		if statusFilter != "" && statusFilter != status {
			continue
		}

		out = append(out, driverLocationResponse{
			DriverID:     d.ID,
			FullName:     d.FullName,
			Phone:        d.Phone,
			VehiclePlate: d.VehiclePlate,
			Status:       status,
			Lat:          loc.Lat,
			Lng:          loc.Lng,
			LastSeenAt:   loc.UpdatedAt.Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, out)
}

func withinCityBounds(lat, lng float64, area *servicearea.ServiceArea) bool {
	return area.Contains(lat, lng)
}
