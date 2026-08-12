package http

import (
	"log"
	"net/http"
)

// writeInternalError logs the underlying error server-side and responds with a
// generic 500 so SQL/database/provider details never leak into the response
// body. Callers must NOT pass client-visible domain messages to it.
func writeInternalError(w http.ResponseWriter, err error) {
	if err != nil {
		log.Printf("ERROR: %v", err)
	}
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
}

// writeUpstreamError logs an infrastructure/provider failure and responds with
// a safe generic message at the given gateway status (502/503/504). The full
// detail stays in the server log.
func writeUpstreamError(w http.ResponseWriter, status int, err error) {
	if err != nil {
		log.Printf("ERROR: %v", err)
	}
	writeJSON(w, status, map[string]string{"error": "upstream service error"})
}

// writeSafeError logs the underlying error (when present) and responds with a
// fixed client message at the given status. Use it where an infrastructure
// failure must be hidden behind a non-500 status (e.g. a webhook that has to
// answer 4xx so the provider does not silently retry forever).
func writeSafeError(w http.ResponseWriter, status int, message string, err error) {
	if err != nil {
		log.Printf("ERROR: %v", err)
	}
	writeJSON(w, status, map[string]string{"error": message})
}
