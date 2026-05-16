package driver

import (
	"context"
	"testing"
	"time"
)

type fakeGateRepo struct {
	docsApproved       bool
	taxVerified        bool
	subscriptionActive bool
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

func TestGateServiceRequiresApprovedDocuments(t *testing.T) {
	uc := NewGateService(fakeGateRepo{taxVerified: true, subscriptionActive: true}, fakeClock{now: time.Now()}, true, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != ErrDriverDocumentsNotApproved {
		t.Fatalf("expected documents gate error, got %v", err)
	}
}

func TestGateServiceRequiresVerifiedTax(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: true, subscriptionActive: true}, fakeClock{now: time.Now()}, true, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != ErrDriverTaxNotVerified {
		t.Fatalf("expected tax gate error, got %v", err)
	}
}

func TestGateServiceRequiresSubscriptionWhenConfigured(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: true, taxVerified: true}, fakeClock{now: time.Now()}, true, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != ErrDriverSubscriptionInactive {
		t.Fatalf("expected subscription gate error, got %v", err)
	}
}

func TestGateServiceAllowsWorkWhenAllRequirementsPass(t *testing.T) {
	uc := NewGateService(fakeGateRepo{docsApproved: true, taxVerified: true, subscriptionActive: true}, fakeClock{now: time.Now()}, true, false)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected gate to pass, got %v", err)
	}
}

func TestGateServiceBypassAllowsScenarioTesting(t *testing.T) {
	uc := NewGateService(fakeGateRepo{}, fakeClock{now: time.Now()}, true, true)

	if err := uc.EnsureCanWork(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected work gate bypass to pass, got %v", err)
	}
	if err := uc.EnsureCanRequestPayout(context.Background(), "driver-1"); err != nil {
		t.Fatalf("expected payout gate bypass to pass, got %v", err)
	}
}
