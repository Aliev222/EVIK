package http

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	orderdomain "evik/backend/internal/domain/order"
	pricingdomain "evik/backend/internal/domain/pricing"
)

type PricingHandler struct {
	service pricingdomain.Service
}

func NewPricingHandler(service pricingdomain.Service) *PricingHandler {
	return &PricingHandler{
		service: service,
	}
}

type calculatePriceRequest struct {
	PickupLat    float64 `json:"pickup_lat"`
	PickupLng    float64 `json:"pickup_lng"`
	DropoffLat   float64 `json:"dropoff_lat"`
	DropoffLng   float64 `json:"dropoff_lng"`
	TowTruckType string  `json:"tow_truck_type"`
}

type calculatePriceResponse struct {
	OrderID       string  `json:"order_id"`
	DistanceKm    float64 `json:"distance_km"`
	BasePrice     int64   `json:"base_price"`
	DistancePrice int64   `json:"distance_price"`
	TotalPrice    int64   `json:"total_price"`
	TariffID      string  `json:"tariff_id"`
	Currency      string  `json:"currency"`
}

type tariffResponse struct {
	ID           string `json:"id"`
	TowTruckType string `json:"tow_truck_type"`
	BasePrice    int64  `json:"base_price"`
	PricePerKm   int64  `json:"price_per_km"`
	MinimumPrice int64  `json:"minimum_price"`
	IsActive     bool   `json:"is_active"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
}

// CalculatePrice calculates the price for a potential order
func (h *PricingHandler) CalculatePrice(w http.ResponseWriter, r *http.Request) {
	var req calculatePriceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Generate temporary order ID for calculation
	orderID := "calc-" + strconv.FormatInt(time.Now().Unix(), 36)

	input := pricingdomain.CalculatePriceInput{
		OrderID:      orderID,
		PickupLat:    req.PickupLat,
		PickupLng:    req.PickupLng,
		DropoffLat:   req.DropoffLat,
		DropoffLng:   req.DropoffLng,
		TowTruckType: orderdomain.TowTruckType(req.TowTruckType),
	}

	calculation, err := h.service.CalculatePrice(r.Context(), input)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	response := calculatePriceResponse{
		OrderID:       calculation.OrderID,
		DistanceKm:    calculation.DistanceKm,
		BasePrice:     calculation.BasePrice,
		DistancePrice: calculation.DistancePrice,
		TotalPrice:    calculation.TotalPrice,
		TariffID:      calculation.TariffID,
		Currency:      "RUB",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GetTariffs returns all active tariffs
func (h *PricingHandler) GetTariffs(w http.ResponseWriter, r *http.Request) {
	tariffs, err := h.service.GetAllTariffs(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	response := make([]tariffResponse, len(tariffs))
	for i, tariff := range tariffs {
		response[i] = tariffResponse{
			ID:           tariff.ID,
			TowTruckType: string(tariff.TowTruckType),
			BasePrice:    tariff.BasePrice,
			PricePerKm:   tariff.PricePerKm,
			MinimumPrice: tariff.MinimumPrice,
			IsActive:     tariff.IsActive,
			CreatedAt:    tariff.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
			UpdatedAt:    tariff.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"tariffs": response,
	})
}

// GetTariffByType returns the active tariff for a specific tow truck type
func (h *PricingHandler) GetTariffByType(w http.ResponseWriter, r *http.Request) {
	truckTypeStr := chi.URLParam(r, "type")
	truckType := orderdomain.TowTruckType(truckTypeStr)

	if !truckType.IsValid() {
		http.Error(w, "Invalid tow truck type", http.StatusBadRequest)
		return
	}

	tariff, err := h.service.GetActiveTariff(r.Context(), truckType)
	if err != nil {
		if err == pricingdomain.ErrTariffNotFound {
			http.Error(w, "Tariff not found", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	response := tariffResponse{
		ID:           tariff.ID,
		TowTruckType: string(tariff.TowTruckType),
		BasePrice:    tariff.BasePrice,
		PricePerKm:   tariff.PricePerKm,
		MinimumPrice: tariff.MinimumPrice,
		IsActive:     tariff.IsActive,
		CreatedAt:    tariff.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:    tariff.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}