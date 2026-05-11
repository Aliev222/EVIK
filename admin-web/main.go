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
	addr          string
	apiBaseURL    string
	promapsAPIKey string
}

func main() {
	cfg := config{
		addr:          getEnv("ADMIN_WEB_ADDR", ":5174"),
		apiBaseURL:    strings.TrimRight(getEnv("EVIK_API_BASE_URL", "https://tow-truck.onrender.com"), "/"),
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
			"api_base_url":     cfg.apiBaseURL,
			"admin_api_prefix": "/api/v1/admin",
			"promaps_api_key":  cfg.promapsAPIKey,
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

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
