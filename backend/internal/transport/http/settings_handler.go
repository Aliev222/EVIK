package http

import (
	"encoding/json"
	"net/http"

	"evik/backend/internal/domain/settings"
)

type SettingsHandler struct {
	repo settings.Repository
}

func NewSettingsHandler(repo settings.Repository) *SettingsHandler {
	return &SettingsHandler{repo: repo}
}

func (h *SettingsHandler) List(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.List(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *SettingsHandler) Update(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Key   string `json:"key"`
		Value any    `json:"value"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if req.Key == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "key is required"})
		return
	}
	if err := h.repo.Upsert(r.Context(), req.Key, req.Value); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}
