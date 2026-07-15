package http

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	orderdomain "evik/backend/internal/domain/order"
	"github.com/go-chi/chi/v5"
)

type offerRepository interface {
	GetActiveForDriver(ctx context.Context, driverID string) (*orderdomain.Offer, error)
	ResolveByOrderAndDriver(ctx context.Context, orderID, driverID string, outcome string) error
}

type OfferHandler struct {
	offerRepo offerRepository
	orderRepo orderAccessRepository
}

func NewOfferHandler(offerRepo offerRepository, orderRepo orderAccessRepository) *OfferHandler {
	return &OfferHandler{offerRepo: offerRepo, orderRepo: orderRepo}
}

func (h *OfferHandler) DeclineOffer(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	if err := h.offerRepo.ResolveByOrderAndDriver(r.Context(), orderID, driverID, "declined"); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "no active offer for this order"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "declined"})
}

func (h *OfferHandler) GetCurrentOffer(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	offer, err := h.offerRepo.GetActiveForDriver(r.Context(), driverID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if offer == nil {
		writeJSON(w, http.StatusOK, map[string]any{"offer": nil})
		return
	}

	ord, err := h.orderRepo.GetByID(r.Context(), offer.OrderID)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"offer": nil})
		return
	}

	resp := map[string]any{
		"offer_id":        offer.ID,
		"order_id":        offer.OrderID,
		"expires_at":      offer.ExpiresAt.UTC().Format("2006-01-02T15:04:05.000Z07:00"),
		"pickup_lat":      ord.Pickup.Lat,
		"pickup_lng":      ord.Pickup.Lng,
		"dropoff_lat":     ord.Dropoff.Lat,
		"dropoff_lng":     ord.Dropoff.Lng,
		"pickup_address":  ord.PickupAddress,
		"dropoff_address": ord.DropoffAddress,
		"distance_km":     nil,
		"price_total":     ord.PriceTotal,
		"tow_truck_type":  string(ord.TowTruckType),
	}
	if offer.DistanceKM != nil {
		resp["distance_km"] = *offer.DistanceKM
	}

	writeJSON(w, http.StatusOK, map[string]any{"offer": resp})
}
