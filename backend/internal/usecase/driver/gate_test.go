package driver

import (
	"context"
	"errors"
	"testing"
	"time"

	"evik/backend/internal/domain/settings"
)

type fakeGateRepo struct {
	docsApproved       bool
	taxVerified        bool
	subscriptionActive bool
	debtBalance        int64
	debtErr            error
}

func (r fakeGateRepo) IsDriverDocumentsApproved(context.Context, string) (bool, error) {
	return r.docsApproved, nil
}

func (r fakeGateRepo) IsDriverTaxVerified(context.Context, string) (bool, error) {
	return r.taxVerified, nil
}

func (r fakeGateRepo) IsDriverSubscriptionActive(context.Context, string, time.Time) (bool, error) {
	return r.subscriptionActive, nil
}

func (r fakeGateRepo) DriverDebtBalance(context.Context, string) (int64, error) {
	return r.debtBalance, r.debtErr
}

type fakeDebtSettingsRepo struct {
	maxCashDebtKopecks int
}

func (f fakeDebtSettingsRepo) List(context.Context) ([]settings.Setting, error) {
	return []settings.Setting{{
		Key:   settings.MaxCashDebtKopecksKey,
		Value: float64(f.maxCashDebtKopecks),
	}}, nil
}

func (fakeDebtSettingsRepo) Upsert(context.Context, string, any) error {
	return nil
}

// fakeMissingSettingsRepo returns no settings at all, forcing the default debt
// threshold (settings.DefaultMaxCashDebtKopecks) to apply.
type fakeMissingSettingsRepo struct{}

func (fakeMissingSettingsRepo) List(context.Context) ([]settings.Setting, error) {
	return nil, nil
}

func (fakeMissingSettingsRepo) Upsert(context.Context, string, any) error {
	return nil
}

func newTestGate(settingsRepo settings.Repository) *GateService {
	return NewGateService(
		fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true},
		settingsRepo,
		fakeClock{now: time.Now()},
		true, false, false,
	)
}

func TestGateServiceRequiresApprovedDocuments(t *testing.T) {
	uc := NewGateService(fakeGateRepo{taxVerified: true, subscriptionActive: true}, fakeDebtSettingsRepo{}, fakeClock{now: time.Now()}, true, false, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != ErrDriverDocumentsNotApproved {
		t.Fatalf("expected documents gate error, got %v", err)
	}
}

func TestGateServiceRequiresVerifiedTax(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: true, subscriptionActive: true}, fakeDebtSettingsRepo{}, fakeClock{now: time.Now()}, true, false, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != ErrDriverTaxNotVerified {
		t.Fatalf("expected tax gate error, got %v", err)
	}
}

func TestGateServiceRequiresSubscriptionWhenConfigured(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: true, taxVerified: true}, fakeDebtSettingsRepo{}, fakeClock{now: time.Now()}, true, false, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != ErrDriverSubscriptionInactive {
		t.Fatalf("expected subscription gate error, got %v", err)
	}
}

func TestGateServiceAllowsWorkWhenAllRequirementsPass(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected gate to pass, got %v", err)
	}
}

func TestGateServiceBypassAllowsScenarioTesting(t *testing.T) {
	uc := NewGateService(fakeGateRepo{}, fakeDebtSettingsRepo{}, fakeClock{now: time.Now()}, true, true, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected work gate bypass to pass, got %v", err)
	}
	if err := uc.EnsureCanRequestPayout(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected payout gate bypass to pass, got %v", err)
	}
}

// A driver whose verification is not approved (e.g. blocked) must still be
// able to request a payout of already-earned money. The payout gate must NOT
// depend on driver_verifications.status.
func TestGateServiceRequestPayoutAllowsNotApprovedDriver(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: false, taxVerified: true, debtBalance: 99999999}, fakeDebtSettingsRepo{maxCashDebtKopecks: 100000}, fakeClock{now: time.Now()}, true, false, false)

	// A huge outstanding debt must NOT block withdrawing already-earned money.
	if err := uc.EnsureCanRequestPayout(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected not-approved driver with debt to pass payout gate, got %v", err)
	}
}

// Tax verification is the only gate on payout: a driver without a verified
// tax profile cannot withdraw regardless of moderation status.
func TestGateServiceRequestPayoutRequiresVerifiedTax(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: false, taxVerified: false}, fakeDebtSettingsRepo{}, fakeClock{now: time.Now()}, true, false, false)

	if err := uc.EnsureCanRequestPayout(context.Background(), "driver-1"); err != ErrDriverTaxNotVerified {
		t.Fatalf("expected tax gate error, got %v", err)
	}
}

func TestGateServiceDebtBeneathThresholdAllowsWork(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 99999}

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected work gate to pass with debt at threshold-1, got %v", err)
	}
}

func TestGateServiceDebtAtThresholdAllowsWork(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 100000}

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected work gate to pass with debt equal to threshold, got %v", err)
	}
}

func TestGateServiceDebtAboveThresholdBlocksWork(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 100001}

	err := uc.EnsureCanWork(context.Background(), "driver-1")
	if !errors.Is(err, ErrOutstandingDebtBlocksWork) {
		t.Fatalf("expected debt gate error, got %v", err)
	}
}

func TestGateServiceDebtGateDisabledWhenThresholdZero(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 0})
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 100000000}

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected gate to be disabled (threshold=0), got %v", err)
	}
}

// Subscription active + 0% commission → no debt accrues → the debt gate must
// trivially pass (debtBalance 0).
func TestGateServiceNoDebtWithActiveSubscriptionAllowsWork(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 0}

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected gate to pass with zero debt, got %v", err)
	}
}

// Simulates a debt repayment (or card-order auto-repayment) that brings debt
// back under the threshold: the driver must be unblocked.
func TestGateServiceDebtRepaymentUnblocksWork(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})

	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 150000}
	if err := uc.EnsureCanWork(context.Background(), "driver-1"); !errors.Is(err, ErrOutstandingDebtBlocksWork) {
		t.Fatalf("expected debt gate error before repayment, got %v", err)
	}

	// Debt repaid in full (0) or down to the threshold → unblocked.
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 80000}
	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected work gate to pass after repayment, got %v", err)
	}

	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 0}
	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected work gate to pass with zero debt after full repayment, got %v", err)
	}
}

// When the debt threshold setting is absent, the default applies and an
// over-threshold debt must still block work.
func TestGateServiceDebtBlocksWhenSettingMissing(t *testing.T) {
	uc := NewGateService(
		fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtBalance: 200000},
		fakeDebtSettingsRepo{maxCashDebtKopecks: 0}, // List returns no matching key
		fakeClock{now: time.Now()},
		true, false, false,
	)
	uc.settingsRepo = fakeMissingSettingsRepo{}

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); !errors.Is(err, ErrOutstandingDebtBlocksWork) {
		t.Fatalf("expected default threshold to apply and block, got %v", err)
	}
}

func TestGateServiceDebtRepoErrorPropagates(t *testing.T) {
	uc := newTestGate(fakeDebtSettingsRepo{maxCashDebtKopecks: 100000})
	uc.repo = fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true, debtErr: context.Canceled}

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected debt repo error to propagate, got %v", err)
	}
}