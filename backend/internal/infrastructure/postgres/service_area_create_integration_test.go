//go:build integration

package postgres_test

import (
	"context"
	"testing"

	servicearea "evik/backend/internal/domain/servicearea"
	"evik/backend/internal/infrastructure/postgres"
)

func TestServiceAreaRepositoryCreate_PersistsBoundaryBuffer(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	repo := postgres.NewServiceAreaRepository(db)
	area := servicearea.ServiceArea{
		ID:               "create-area",
		Name:             "Тестовый город",
		Slug:             "test-city",
		MinLat:           42.8,
		MinLng:           47.5,
		MaxLat:           43.1,
		MaxLng:           47.8,
		CenterLat:        42.95,
		CenterLng:        47.65,
		RadiusKM:         25,
		PrimaryRadiusKM:  12,
		BoundaryGeoJSON:  `{"type":"Polygon","coordinates":[]}`,
		BoundaryBufferKM: 7,
		IsActive:         true,
	}

	if err := repo.Create(context.Background(), area); err != nil {
		t.Fatalf("Create: %v", err)
	}

	got, err := repo.GetByID(context.Background(), area.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.BoundaryBufferKM != area.BoundaryBufferKM {
		t.Fatalf("boundary buffer = %v, want %v", got.BoundaryBufferKM, area.BoundaryBufferKM)
	}
}
