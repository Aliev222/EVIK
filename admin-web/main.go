package main

import (
	"embed"
	"encoding/json"
	"errors"
	"io/fs"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

//go:embed static/*
var staticFiles embed.FS

type config struct {
	addr            string
	apiBaseURL      string
	promapsAPIKey   string
}

func main() {
	cfg := config{
		addr:          getEnv("ADMIN_WEB_ADDR", ":5174"),
		apiBaseURL:    strings.TrimRight(getEnv("EVIK_API_BASE_URL", "http://localhost:8080"), "/"),
		promapsAPIKey: getEnv("PROMAPS_API_KEY", "pk_live_d44618284239626c98dc23cd909b2b6eff001df7cdecbc5"),
	}

	apiURL, err := url.Parse(cfg.apiBaseURL)
	if err != nil {
		log.Fatalf("invalid EVIK_API_BASE_URL: %v", err)
	}

	staticRoot, err := fs.Sub(staticFiles, "static")
	if err != nil {
		log.Fatalf("static files unavailable: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/admin-api/config", handleConfig(cfg))
	mux.HandleFunc("/admin-api/mock/", handleMock)
	mux.Handle("/api/", newProxy(apiURL))
	mux.Handle("/", spaHandler(staticRoot))

	server := &http.Server{
		Addr:              cfg.addr,
		Handler:           securityHeaders(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("EVIK admin web started on http://127.0.0.1%s", cfg.addr)
	log.Printf("proxying app API to %s", cfg.apiBaseURL)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("admin web failed: %v", err)
	}
}

func getEnv(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("X-Frame-Options", "DENY")
		next.ServeHTTP(w, r)
	})
}

func handleConfig(cfg config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"api_base_url":      cfg.apiBaseURL,
			"admin_api_prefix":  "/api/v1/admin",
			"promaps_api_key":   cfg.promapsAPIKey,
		})
	}
}

func newProxy(target *url.URL) http.Handler {
	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director
	proxy.Director = func(r *http.Request) {
		requestTarget := target
		if headerTarget, err := parseRequestTarget(r.Header.Get("X-Evik-Api-Base-Url")); err == nil && headerTarget != nil {
			requestTarget = headerTarget
		}

		originalDirector(r)
		r.Host = requestTarget.Host
		r.URL.Scheme = requestTarget.Scheme
		r.URL.Host = requestTarget.Host
		r.Header.Del("X-Evik-Api-Base-Url")
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": "app backend unavailable",
		})
	}
	return proxy
}

func parseRequestTarget(raw string) (*url.URL, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}
	parsed, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, errors.New("unsupported api url scheme")
	}
	if parsed.Host == "" {
		return nil, errors.New("api url host is required")
	}
	return parsed, nil
}

func spaHandler(root fs.FS) http.Handler {
	fileServer := http.FileServer(http.FS(root))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/")
		if path == "" {
			path = "index.html"
		}
		if _, err := fs.Stat(root, path); err == nil {
			fileServer.ServeHTTP(w, r)
			return
		}
		r.URL.Path = "/index.html"
		fileServer.ServeHTTP(w, r)
	})
}

func handleMock(w http.ResponseWriter, r *http.Request) {
	switch strings.TrimPrefix(r.URL.Path, "/admin-api/mock/") {
	case "overview":
		writeJSON(w, http.StatusOK, mockOverview())
	case "driver-verifications":
		writeJSON(w, http.StatusOK, map[string]any{"items": mockVerifications()})
	case "users":
		writeJSON(w, http.StatusOK, map[string]any{"items": mockUsers()})
	case "reviews":
		writeJSON(w, http.StatusOK, map[string]any{"items": mockReviews()})
	case "drivers-online":
		writeJSON(w, http.StatusOK, map[string]any{"items": mockOnlineDrivers()})
	default:
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "mock endpoint not found"})
	}
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func mockOverview() map[string]any {
	return map[string]any{
		"total_users":          1842,
		"clients":              1290,
		"drivers":              552,
		"online_drivers":       38,
		"pending_moderations":  12,
		"average_driver_stars": 4.72,
		"reviews_today":        27,
		"active_orders":        19,
	}
}

func mockVerifications() []map[string]any {
	return []map[string]any{
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
		{
			"id": "DRV-1035", "driver_name": "Павел Кузнецов", "phone": "+7 999 774-11-06",
			"city": "Балашиха", "vehicle": "Mercedes Atego", "plate": "О219КМ 750",
			"vehicle_type": "Платформа", "status": "approved", "risk": "low",
			"stars": 4.7, "orders": 51, "submitted_at": time.Now().Add(-30 * time.Hour).Format(time.RFC3339),
			"documents": []string{"Паспорт", "Водительское удостоверение"},
			"signals":   []string{},
		},
	}
}

func mockUsers() []map[string]any {
	return []map[string]any{
		{"id": "USR-1001", "name": "Марина Орлова", "role": "client", "phone": "+7 925 310-44-19", "orders": 8, "status": "active"},
		{"id": "DRV-1041", "name": "Ирина Лебедева", "role": "driver", "phone": "+7 916 442-77-04", "orders": 12, "status": "moderation"},
		{"id": "DRV-1035", "name": "Павел Кузнецов", "role": "driver", "phone": "+7 999 774-11-06", "orders": 51, "status": "active"},
		{"id": "USR-1004", "name": "Сергей Власов", "role": "client", "phone": "+7 901 280-12-00", "orders": 2, "status": "blocked"},
	}
}

func mockReviews() []map[string]any {
	return []map[string]any{
		{"id": "REV-9001", "driver_name": "Павел Кузнецов", "client_name": "Марина Орлова", "stars": 5, "text": "Быстро приехал, аккуратно погрузил машину.", "created_at": time.Now().Add(-2 * time.Hour).Format(time.RFC3339)},
		{"id": "REV-9000", "driver_name": "Ирина Лебедева", "client_name": "Олег Миронов", "stars": 4, "text": "Все хорошо, но ожидание было дольше указанного.", "created_at": time.Now().Add(-7 * time.Hour).Format(time.RFC3339)},
		{"id": "REV-8998", "driver_name": "Дмитрий Соколов", "client_name": "Анна Ким", "stars": 5, "text": "Водитель помог с документами и был на связи.", "created_at": time.Now().Add(-25 * time.Hour).Format(time.RFC3339)},
	}
}

func mockOnlineDrivers() []map[string]any {
	return []map[string]any{
		{"id": "DRV-203", "name": "Павел Кузнецов", "lat": 55.7558, "lng": 37.6173, "status": "online", "stars": 4.7, "vehicle": "Платформа", "last_seen": time.Now().Add(-2 * time.Minute).Format(time.RFC3339)},
		{"id": "DRV-188", "name": "Дмитрий Соколов", "lat": 55.7811, "lng": 37.6092, "status": "online", "stars": 4.9, "vehicle": "Манипулятор", "last_seen": time.Now().Add(-4 * time.Minute).Format(time.RFC3339)},
		{"id": "DRV-175", "name": "Ирина Лебедева", "lat": 55.7424, "lng": 37.6247, "status": "busy", "stars": 4.8, "vehicle": "Лебедка", "last_seen": time.Now().Add(-1 * time.Minute).Format(time.RFC3339)},
		{"id": "DRV-169", "name": "Андрей Новиков", "lat": 55.7936, "lng": 37.7015, "status": "online", "stars": 4.6, "vehicle": "Платформа", "last_seen": time.Now().Add(-6 * time.Minute).Format(time.RFC3339)},
	}
}
