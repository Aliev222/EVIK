package app

import (
	"log"
	"os"
	"path/filepath"
)

// resolveAdminStaticDir tries a fixed list of candidate directories for the
// admin panel's static assets and returns the first absolute path that
// actually contains index.html. Render's working directory for the Go
// buildpack isn't guaranteed to be backend/, so a single relative path
// (e.g. "../admin-web/static") can silently fail to resolve in production.
// Returns "" when no candidate exists, so the caller can skip mounting
// /admin entirely instead of mounting a handler that 500s on every request.
func resolveAdminStaticDir(configured string, logger *log.Logger) string {
	cwd, err := os.Getwd()
	if err == nil {
		logger.Printf("INFO: working directory: %s", cwd)
	}
	logger.Printf("INFO: admin static dir (configured): %s", configured)

	var candidates []string
	if configured != "" {
		candidates = append(candidates, configured)
	}
	candidates = append(candidates,
		"./admin-web/static",
		"../admin-web/static",
		"/opt/render/project/src/admin-web/static",
	)
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		for i := 0; i < 4; i++ {
			candidates = append(candidates, filepath.Join(dir, "admin-web", "static"))
			dir = filepath.Dir(dir)
		}
	}

	seen := make(map[string]bool, len(candidates))
	for _, candidate := range candidates {
		abs, err := filepath.Abs(candidate)
		if err != nil || seen[abs] {
			continue
		}
		seen[abs] = true
		if info, err := os.Stat(filepath.Join(abs, "index.html")); err == nil && !info.IsDir() {
			logger.Printf("INFO: admin static dir resolved: %s (from candidate %q)", abs, candidate)
			return abs
		}
	}

	logger.Printf("ERROR: admin static dir not found, admin panel disabled (tried %d candidates)", len(seen))
	return ""
}
