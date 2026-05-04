package http

import (
	"encoding/json"
	"net/http"
	"time"

	"evik/backend/internal/auth"
	"github.com/go-chi/chi/v5"
)

type AdminHandler struct {
	// В продакшене - реальные сервисы
	// userRepo usersdomain.Repository
	// driverRepo driverdomain.Repository
	// orderRepo orderdomain.Repository
}

func NewAdminHandler() *AdminHandler {
	return &AdminHandler{}
}

// GET /api/v1/admin/overview
func (h *AdminHandler) GetOverview(w http.ResponseWriter, r *http.Request) {
	// TODO: Реальная статистика из базы
	overview := map[string]interface{}{
		"total_users":          1842,
		"clients":              1290,
		"drivers":              552,
		"online_drivers":       38,
		"pending_moderations":  12,
		"average_driver_stars": 4.72,
		"reviews_today":        27,
		"active_orders":        19,
	}

	h.writeJSON(w, http.StatusOK, overview)
}

// GET /api/v1/admin/driver-verifications
func (h *AdminHandler) GetDriverVerifications(w http.ResponseWriter, r *http.Request) {
	// TODO: Реальные данные модерации из базы
	verifications := []map[string]interface{}{
		{
			"id": "DRV-1042", "driver_name": "Алексей Морозов", "phone": "+7 900 114-22-10",
			"city": "Москва", "vehicle": "ГАЗон Next", "plate": "А471МО 797",
			"vehicle_type": "Платформа", "status": "pending", "risk": "high",
			"stars": 0, "orders": 0, "submitted_at": time.Now().Add(-29 * time.Hour).Format(time.RFC3339),
			"documents": []string{"Паспорт", "Водительское удостоверение", "СТС"},
			"signals":   []string{"Номер автомобиля отличается от анкеты", "Заявка старше SLA 24 часа"},
		},
		{
			"id": "DRV-1041", "driver_name": "Ирина Лебедева", "phone": "+7 916 442-77-04",
			"city": "Химки", "vehicle": "Hyundai HD78", "plate": "М518ЕР 799",
			"vehicle_type": "Лебедка", "status": "pending", "risk": "medium",
			"stars": 4.8, "orders": 12, "submitted_at": time.Now().Add(-6 * time.Hour).Format(time.RFC3339),
			"documents": []string{"Паспорт", "Водительское удостоверение", "Страховка"},
			"signals":   []string{"Страховка истекает менее чем через 30 дней"},
		},
	}

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": verifications,
	})
}

// GET /api/v1/admin/users
func (h *AdminHandler) GetUsers(w http.ResponseWriter, r *http.Request) {
	// TODO: Реальные пользователи из базы
	users := []map[string]interface{}{
		{"id": "USR-1001", "name": "Марина Орлова", "role": "client", "phone": "+7 925 310-44-19", "orders": 8, "status": "active"},
		{"id": "DRV-1041", "name": "Ирина Лебедева", "role": "driver", "phone": "+7 916 442-77-04", "orders": 12, "status": "moderation"},
		{"id": "DRV-1035", "name": "Павел Кузнецов", "role": "driver", "phone": "+7 999 774-11-06", "orders": 51, "status": "active"},
		{"id": "USR-1004", "name": "Сергей Власов", "role": "client", "phone": "+7 901 280-12-00", "orders": 2, "status": "blocked"},
	}

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": users,
	})
}

// GET /api/v1/admin/reviews
func (h *AdminHandler) GetReviews(w http.ResponseWriter, r *http.Request) {
	// TODO: Реальные отзывы из базы
	reviews := []map[string]interface{}{
		{"id": "REV-9001", "driver_name": "Павел Кузнецов", "client_name": "Марина Орлова", "stars": 5, "text": "Быстро приехал, аккуратно погрузил машину.", "created_at": time.Now().Add(-2 * time.Hour).Format(time.RFC3339)},
		{"id": "REV-9000", "driver_name": "Ирина Лебедева", "client_name": "Олег Миронов", "stars": 4, "text": "Все хорошо, но ожидание было дольше указанного.", "created_at": time.Now().Add(-7 * time.Hour).Format(time.RFC3339)},
		{"id": "REV-8998", "driver_name": "Дмитрий Соколов", "client_name": "Анна Ким", "stars": 5, "text": "Водитель помог с документами и был на связи.", "created_at": time.Now().Add(-25 * time.Hour).Format(time.RFC3339)},
	}

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": reviews,
	})
}

// GET /api/v1/admin/drivers-online
func (h *AdminHandler) GetDriversOnline(w http.ResponseWriter, r *http.Request) {
	// TODO: Реальные онлайн водители из базы/Redis
	drivers := []map[string]interface{}{
		{"id": "DRV-203", "name": "Павел Кузнецов", "lat": 55.7558, "lng": 37.6173, "status": "online", "stars": 4.7, "vehicle": "Платформа", "last_seen": time.Now().Add(-2 * time.Minute).Format(time.RFC3339)},
		{"id": "DRV-188", "name": "Дмитрий Соколов", "lat": 55.7811, "lng": 37.6092, "status": "online", "stars": 4.9, "vehicle": "Манипулятор", "last_seen": time.Now().Add(-4 * time.Minute).Format(time.RFC3339)},
		{"id": "DRV-175", "name": "Ирина Лебедева", "lat": 55.7424, "lng": 37.6247, "status": "busy", "stars": 4.8, "vehicle": "Лебедка", "last_seen": time.Now().Add(-1 * time.Minute).Format(time.RFC3339)},
		{"id": "DRV-169", "name": "Андрей Новиков", "lat": 55.7936, "lng": 37.7015, "status": "online", "stars": 4.6, "vehicle": "Платформа", "last_seen": time.Now().Add(-6 * time.Minute).Format(time.RFC3339)},
	}

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": drivers,
	})
}

// POST /api/v1/admin/moderation/driver-verifications/{id}/approve
func (h *AdminHandler) ApproveDriver(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "id")

	var req struct {
		Reason string `json:"reason"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	// TODO: Обновить статус водителя в базе
	// driverService.ApproveVerification(driverID, req.Reason)

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Driver approved",
		"driver_id": driverID,
	})
}

// POST /api/v1/admin/moderation/driver-verifications/{id}/reject
func (h *AdminHandler) RejectDriver(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "id")

	var req struct {
		Reason string `json:"reason"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	// TODO: Отклонить водителя в базе
	// driverService.RejectVerification(driverID, req.Reason)

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Driver rejected",
		"driver_id": driverID,
		"reason": req.Reason,
	})
}

// POST /api/v1/admin/moderation/driver-verifications/{id}/request-changes
func (h *AdminHandler) RequestChanges(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "id")

	var req struct {
		Reason string `json:"reason"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	// TODO: Запросить исправления в базе
	// driverService.RequestChanges(driverID, req.Reason)

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Changes requested",
		"driver_id": driverID,
		"reason": req.Reason,
	})
}

// POST /api/v1/admin/moderation/driver-verifications/{id}/block
func (h *AdminHandler) BlockDriver(w http.ResponseWriter, r *http.Request) {
	driverID := chi.URLParam(r, "id")

	var req struct {
		Reason string `json:"reason"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	// TODO: Заблокировать водителя в базе
	// driverService.BlockDriver(driverID, req.Reason)

	h.writeJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Driver blocked",
		"driver_id": driverID,
		"reason": req.Reason,
	})
}

func (h *AdminHandler) RequireAdmin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Проверяем что пользователь админ
		role, err := roleFromContext(r.Context())
		if err != nil || role != auth.RoleAdmin {
			writeAuthError(w, http.StatusForbidden, "admin access required")
			return
		}
		next(w, r)
	}
}

func (h *AdminHandler) writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(payload)
}