package config

import (
	"strings"
	"testing"
)

func validProductionConfig() Config {
	return Config{
		AppEnv:             "production",
		JWTSecret:          strings.Repeat("s", 32),
		AllowedOrigins:     []string{"https://admin.avro.example"},
		AdminUserID:        "admin",
		AdminPassword:      "strong-password",
		S3Endpoint:         "https://s3.example",
		S3Bucket:           "documents",
		S3AccessKey:        "key",
		S3SecretKey:        "secret",
		S3PublicBaseURL:    "https://cdn.example",
		YooKassaShopID:     "shop",
		YooKassaSecret:     "payment-secret",
		YooKassaPayoutMode: "disabled",
		TrustedProxyCIDRs:  []string{"127.0.0.0/8"},
	}
}

func TestProductionConfigRejectsFakeFinancialModes(t *testing.T) {
	for name, mutate := range map[string]func(*Config){
		"payment stub":              func(cfg *Config) { cfg.YooKassaStubMode = true },
		"sandbox payout":            func(cfg *Config) { cfg.YooKassaPayoutMode = "sandbox" },
		"unimplemented live payout": func(cfg *Config) { cfg.YooKassaPayoutMode = "live" },
	} {
		t.Run(name, func(t *testing.T) {
			cfg := validProductionConfig()
			mutate(&cfg)
			if problems := productionConfigProblems(cfg); len(problems) == 0 {
				t.Fatal("production config accepted fake or incomplete payout mode")
			}
		})
	}
}

func TestProductionConfigAcceptsPayoutsDisabledUntilRecipientOnboarding(t *testing.T) {
	if problems := productionConfigProblems(validProductionConfig()); len(problems) != 0 {
		t.Fatalf("problems = %#v, want none", problems)
	}
}
