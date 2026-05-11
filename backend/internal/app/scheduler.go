package app

import (
	"context"
	"log"
	"time"

	paymentuc "evik/backend/internal/usecase/payment"
)

const balanceReleaseBatchLimit = 1000

type Scheduler struct {
	finance  *paymentuc.FinanceUseCase
	logger   *log.Logger
	interval time.Duration
}

func NewScheduler(finance *paymentuc.FinanceUseCase, logger *log.Logger, interval time.Duration) *Scheduler {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	return &Scheduler{finance: finance, logger: logger, interval: interval}
}

func (s *Scheduler) Run(ctx context.Context) {
	s.logger.Printf("scheduler started, balance release interval=%s", s.interval)
	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	s.releasePendingBalances(ctx)
	for {
		select {
		case <-ctx.Done():
			s.logger.Printf("scheduler stopped")
			return
		case <-ticker.C:
			s.releasePendingBalances(ctx)
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
