package main

import (
	"embed"
	"io/fs"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

//go:embed static/*
var staticFS embed.FS

const defaultAddr = ":5174"
const defaultBackend = "http://localhost:8080"

func main() {
	// PORT is the conventional pass-through used by PaaS (e.g. Render); it
	// takes precedence over the explicit ADMIN_WEB_ADDR override.
	addr := envOr("PORT", envOr("ADMIN_WEB_ADDR", defaultAddr))
	backendRaw := envOr("ADMIN_API_BASE_URL", defaultBackend)

	target, err := url.Parse(backendRaw)
	if err != nil {
		log.Fatalf("invalid ADMIN_API_BASE_URL %q: %v", backendRaw, err)
	}
	if target.Scheme == "" || target.Host == "" {
		log.Fatalf("ADMIN_API_BASE_URL must include scheme and host, got %q", backendRaw)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = target.Host
		req.Header.Del("X-Evik-Api-Base-Url")
	}

	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		log.Fatalf("embed static: %v", err)
	}
	fileServer := http.FileServer(http.FS(sub))

	mux := http.NewServeMux()

	mux.HandleFunc("/api/v1/", func(w http.ResponseWriter, r *http.Request) {
		proxy.ServeHTTP(w, r)
	})

	mux.HandleFunc("/ws/", func(w http.ResponseWriter, r *http.Request) {
		proxy.ServeHTTP(w, r)
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			http.NotFound(w, r)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/ws/") {
			http.NotFound(w, r)
			return
		}
		path := strings.TrimPrefix(r.URL.Path, "/")
		if path == "" {
			serveIndex(w, r, sub)
			return
		}
		if _, err := fs.Stat(sub, path); err != nil {
			serveIndex(w, r, sub)
			return
		}
		fileServer.ServeHTTP(w, r)
	})

	log.Printf("admin-web listening on %s, proxying /api/v1/* -> %s", addr, target)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

func serveIndex(w http.ResponseWriter, r *http.Request, sub fs.FS) {
	data, err := fs.ReadFile(sub, "index.html")
	if err != nil {
		http.Error(w, "index.html missing", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(data)
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
