package app

import (
	"context"
	"log"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
	paymentuc "evik/backend/internal/usecase/payment"
)

const balanceReleaseBatchLimit = 1000

const stuckPayoutCheckInterval = 6 * time.Hour
const stuckPayoutThreshold = 24 * time.Hour

type Scheduler struct {
	finance           *paymentuc.FinanceUseCase
	paymentRepo       paymentdomain.Repository
	logger            *log.Logger
	interval          time.Duration
}

func NewScheduler(finance *paymentuc.FinanceUseCase, paymentRepo paymentdomain.Repository, logger *log.Logger, interval time.Duration) *Scheduler {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	return &Scheduler{finance: finance, paymentRepo: paymentRepo, logger: logger, interval: interval}
}

func (s *Scheduler) Run(ctx context.Context) {
	s.logger.Printf("scheduler started, balance release interval=%s, stuck payout check interval=%s", s.interval, stuckPayoutCheckInterval)
	ticker := time.NewTicker(s.interval)
	stuckTicker := time.NewTicker(stuckPayoutCheckInterval)
	defer ticker.Stop()
	defer stuckTicker.Stop()

	s.releasePendingBalances(ctx)
	s.checkStuckPayouts(ctx)
	for {
		select {
		case <-ctx.Done():
			s.logger.Printf("scheduler stopped")
			return
		case <-ticker.C:
			s.releasePendingBalances(ctx)
		case <-stuckTicker.C:
			s.checkStuckPayouts(ctx)
		}
	}
}

func (s *Scheduler) releasePendingBalances(ctx context.Context) {
	total := 0
	for {
		count, err := s.finance.ReleasePendingBalances(ctx, balanceReleaseBatchLimit)
		total += count
		if err != nil {
			s.logger.Printf("balance release failed: released=%d err=%v", count, err)
		}
		if count < balanceReleaseBatchLimit {
			break
		}
		if ctx.Err() != nil {
			break
		}
	}
	if total > 0 {
		s.logger.Printf("released %d pending transactions", total)
	}
}

func (s *Scheduler) checkStuckPayouts(ctx context.Context) {
	payouts, err := s.paymentRepo.ListStuckPayouts(ctx, stuckPayoutThreshold)
	if err != nil {
		s.logger.Printf("CRITICAL: stuck payout check failed: %v", err)
		return
	}
	for _, p := range payouts {
		s.logger.Printf("CRITICAL: stuck payout id=%s driver_id=%s created_at=%s", p.ID, p.DriverID, p.CreatedAt.Format(time.RFC3339))
	}
	if len(payouts) > 0 {
		s.logger.Printf("CRITICAL: found %d stuck payouts", len(payouts))
	}
}
