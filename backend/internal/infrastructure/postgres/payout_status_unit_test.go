package postgres

import (
	"testing"

	paymentdomain "evik/backend/internal/domain/payment"
)

func TestPayoutIsApprovable_ExcludesFailed(t *testing.T) {
	if payoutIsApprovable(paymentdomain.PayoutStatusFailed) {
		t.Fatalf("failed payout must not be approvable")
	}
	if !payoutIsApprovable(paymentdomain.PayoutStatusCreated) {
		t.Fatalf("created payout must be approvable")
	}
	if !payoutIsApprovable(paymentdomain.PayoutStatusProcessing) {
		t.Fatalf("processing payout must be approvable")
	}
	if !payoutIsApprovable(paymentdomain.PayoutStatusManualReview) {
		t.Fatalf("manual_review payout must be approvable")
	}
	for _, st := range []paymentdomain.PayoutStatus{
		paymentdomain.PayoutStatusPaid,
		paymentdomain.PayoutStatusCancelled,
	} {
		if payoutIsApprovable(st) {
			t.Fatalf("payout status %q must not be approvable", st)
		}
	}
}
