package http

import (
	"net"
	"net/http"
	"strings"
)

// TrustedProxyRealIP accepts forwarded client-IP headers only when the TCP
// peer belongs to an explicitly configured proxy network. It also removes the
// headers before downstream middleware so direct clients cannot spoof rate
// limits or payment-webhook source verification.
func TrustedProxyRealIP(trustedCIDRs []string) func(http.Handler) http.Handler {
	trustedNetworks := make([]*net.IPNet, 0, len(trustedCIDRs))
	for _, raw := range trustedCIDRs {
		_, network, err := net.ParseCIDR(strings.TrimSpace(raw))
		if err == nil {
			trustedNetworks = append(trustedNetworks, network)
		}
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			peerIP := net.ParseIP(remoteIP(r.RemoteAddr))
			if peerIP != nil && ipInNetworks(peerIP, trustedNetworks) {
				forwarded := strings.TrimSpace(r.Header.Get("X-Real-IP"))
				if forwarded == "" {
					forwarded = firstForwardedIP(r.Header.Get("X-Forwarded-For"))
				}
				if net.ParseIP(forwarded) != nil {
					r.RemoteAddr = forwarded
				}
			}

			r.Header.Del("X-Real-IP")
			r.Header.Del("X-Forwarded-For")
			next.ServeHTTP(w, r)
		})
	}
}

func firstForwardedIP(value string) string {
	if index := strings.Index(value, ","); index >= 0 {
		value = value[:index]
	}
	return strings.TrimSpace(value)
}

func remoteIP(remoteAddr string) string {
	trimmed := strings.TrimSpace(remoteAddr)
	if net.ParseIP(trimmed) != nil {
		return trimmed
	}
	host, _, err := net.SplitHostPort(trimmed)
	if err != nil {
		return strings.Trim(trimmed, "[]")
	}
	return host
}

func ipInNetworks(ip net.IP, networks []*net.IPNet) bool {
	for _, network := range networks {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}
