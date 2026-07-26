package app

import (
	"context"
	"database/sql"
	"log"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/postgres"
)

type stuckDriverRepo interface {
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
	ReleaseOrderTx(ctx context.Context, tx *sql.Tx, driverID string, orderID string, now time.Time) error
}

type stuckOrderRepo interface {
	ListByStatus(ctx context.Context, status orderdomain.Status, limit int) ([]*orderdomain.Order, error)
	GetByID(ctx context.Context, id string) (*orderdomain.Order, error)
	Update(ctx context.Context, ord *orderdomain.Order) error
	UpdateTx(ctx context.Context, tx *sql.Tx, ord *orderdomain.Order) error
}

type stuckDBProvider interface {
	BeginTx(ctx context.Context, opts *sql.TxOptions) (*sql.Tx, error)
}

type stuckEventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type StuckOrderReaper struct {
	db             *sql.DB
	orderRepo      stuckOrderRepo
	driverRepo     stuckDriverRepo
	eventPublisher stuckEventPublisher
	logger         *log.Logger
	checkInterval  time.Duration

	searchingTimeout            time.Duration
	acceptedTimeout             time.Duration
	arrivedFlagThreshold        time.Duration
	inProgressFlagThreshold     time.Duration
	awaitingPaymentFlagThreshold time.Duration
	acceptedAction              string // "cancel" or "flag"
}

func NewStuckOrderReaper(
	db *sql.DB,
	orderRepo stuckOrderRepo,
	driverRepo stuckDriverRepo,
	eventPublisher stuckEventPublisher,
	logger *log.Logger,
	checkInterval time.Duration,
	searchingTimeout time.Duration,
	acceptedTimeout time.Duration,
	arrivedFlagThreshold time.Duration,
	inProgressFlagThreshold time.Duration,
	awaitingPaymentFlagThreshold time.Duration,
	acceptedAction string,
) *StuckOrderReaper {
	if checkInterval <= 0 {
		checkInterval = 30 * time.Second
	}
	if searchingTimeout <= 0 {
		searchingTimeout = 5 * time.Minute
	}
	if acceptedTimeout <= 0 {
		acceptedTimeout = 15 * time.Minute
	}
	if arrivedFlagThreshold <= 0 {
		arrivedFlagThreshold = 2 * time.Hour
	}
	if inProgressFlagThreshold <= 0 {
		inProgressFlagThreshold = 4 * time.Hour
	}
	if awaitingPaymentFlagThreshold <= 0 {
		awaitingPaymentFlagThreshold = 24 * time.Hour
	}
	if acceptedAction != "cancel" && acceptedAction != "flag" {
		acceptedAction = "cancel"
	}
	return &StuckOrderReaper{
		db:                          db,
		orderRepo:                   orderRepo,
		driverRepo:                  driverRepo,
		eventPublisher:              eventPublisher,
		logger:                      logger,
		checkInterval:               checkInterval,
		searchingTimeout:            searchingTimeout,
		acceptedTimeout:             acceptedTimeout,
		arrivedFlagThreshold:        arrivedFlagThreshold,
		inProgressFlagThreshold:     inProgressFlagThreshold,
		awaitingPaymentFlagThreshold: awaitingPaymentFlagThreshold,
		acceptedAction:              acceptedAction,
	}
}

func (r *StuckOrderReaper) Run(ctx context.Context) {
	r.logger.Printf("stuck order reaper started: check=%s searching_to=%s accepted_to=%s accepted_action=%s arrived_flag=%s in_progress_flag=%s awaiting_payment_flag=%s",
		r.checkInterval, r.searchingTimeout, r.acceptedTimeout, r.acceptedAction,
		r.arrivedFlagThreshold, r.inProgressFlagThreshold, r.awaitingPaymentFlagThreshold)
	ticker := time.NewTicker(r.checkInterval)
	defer ticker.Stop()

	r.reapStuckOrders(ctx)
	for {
		select {
		case <-ctx.Done():
			r.logger.Printf("stuck order reaper stopped")
			return
		case <-ticker.C:
			r.reapStuckOrders(ctx)
		}
	}
}

func (r *StuckOrderReaper) reapStuckOrders(ctx context.Context) {
	defer func() {
		if rec := recover(); rec != nil {
			r.logger.Printf("stuck order reaper: panic recovered: %v", rec)
		}
	}()

	now := time.Now().UTC()

	r.reapSearching(ctx, now)
	r.reapAccepted(ctx, now)
	r.reapArrived(ctx, now)
	r.reapInProgress(ctx, now)
	r.reapAwaitingPayment(ctx, now)
}

// reapSearching cancels orders stuck in searching with no driver found.
// Only acts on orders that have been expanded (dispatch tried all rounds + expansion).
func (r *StuckOrderReaper) reapSearching(ctx context.Context, now time.Time) {
	cutoff := now.Add(-r.searchingTimeout)
	orders, err := r.orderRepo.ListByStatus(ctx, orderdomain.StatusSearching, 100)
	if err != nil {
		r.logger.Printf("stuck reaper: list searching: %v", err)
		return
	}
	for _, ord := range orders {
		if !ord.IsExpanded {
			continue
		}
		if ord.UpdatedAt.After(cutoff) {
			continue
		}
		ord.Status = orderdomain.StatusNoDriverFound
		ord.UpdatedAt = now
		if err := r.orderRepo.Update(ctx, ord); err != nil {
			r.logger.Printf("stuck reaper: mark no_driver_found order=%s: %v", ord.ID, err)
			continue
		}
		_ = r.eventPublisher.Publish(ctx, orderdomain.Event{
			Type:    orderdomain.EventNoDriverFound,
			OrderID: ord.ID,
			Payload: map[string]any{
				"status": ord.Status,
				"reason": "stuck_order_reaper_timeout",
			},
		})
		r.logger.Printf("stuck reaper: order=%s searching timeout — marked no_driver_found", ord.ID)
	}
}

// reapAccepted handles orders stuck in accepted.
// When acceptedAction="cancel": cancels the order and atomically releases the driver.
// When acceptedAction="flag": logs a warning for manual review.
func (r *StuckOrderReaper) reapAccepted(ctx context.Context, now time.Time) {
	cutoff := now.Add(-r.acceptedTimeout)
	orders, err := r.orderRepo.ListByStatus(ctx, orderdomain.StatusAccepted, 100)
	if err != nil {
		r.logger.Printf("stuck reaper: list accepted: %v", err)
		return
	}
	for _, ord := range orders {
		if ord.UpdatedAt.After(cutoff) {
			continue
		}
		if r.acceptedAction == "flag" {
			r.logger.Printf("stuck reaper: FLAG order=%s accepted stuck for review (driver=%s, age=%s)",
				ord.ID, safeDriverID(ord.DriverID), now.Sub(ord.UpdatedAt).Round(time.Second))
			continue
		}
		r.cancelAcceptedOrder(ctx, ord, now)
	}
}

func (r *StuckOrderReaper) cancelAcceptedOrder(ctx context.Context, ord *orderdomain.Order, now time.Time) {
	if err := ord.TransitionTo(orderdomain.StatusCancelled, now); err != nil {
		r.logger.Printf("stuck reaper: transition cancel order=%s: %v", ord.ID, err)
		return
	}
	err := postgres.WithTx(ctx, r.db, func(tx *sql.Tx) error {
		if err := r.orderRepo.UpdateTx(ctx, tx, ord); err != nil {
			return err
		}
		if ord.DriverID != nil {
			if err := r.driverRepo.ReleaseOrderTx(ctx, tx, *ord.DriverID, ord.ID, now); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		r.logger.Printf("stuck reaper: atomic cancel+release order=%s: %v", ord.ID, err)
		return
	}
	_ = r.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventCancelled,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status":    ord.Status,
			"driver_id": safeDriverID(ord.DriverID),
			"reason":    "stuck_order_reaper_accepted_timeout",
		},
	})
	r.logger.Printf("stuck reaper: order=%s accepted timeout — cancelled, driver=%s released",
		ord.ID, safeDriverID(ord.DriverID))
}

// reapArrived flags orders stuck in arrived for admin attention.
// Never auto-cancels — the tow may legitimately be waiting.
func (r *StuckOrderReaper) reapArrived(ctx context.Context, now time.Time) {
	cutoff := now.Add(-r.arrivedFlagThreshold)
	orders, err := r.orderRepo.ListByStatus(ctx, orderdomain.StatusArrived, 100)
	if err != nil {
		r.logger.Printf("stuck reaper: list arrived: %v", err)
		return
	}
	for _, ord := range orders {
		if ord.UpdatedAt.After(cutoff) {
			continue
		}
		r.logger.Printf("stuck reaper: FLAG order=%s arrived stuck (driver=%s, age=%s) — requires manual review",
			ord.ID, safeDriverID(ord.DriverID), now.Sub(ord.UpdatedAt).Round(time.Second))
	}
}

// reapInProgress flags orders stuck in in_progress for admin attention.
// Never auto-cancels — a long-distance tow can take hours.
func (r *StuckOrderReaper) reapInProgress(ctx context.Context, now time.Time) {
	cutoff := now.Add(-r.inProgressFlagThreshold)
	orders, err := r.orderRepo.ListByStatus(ctx, orderdomain.StatusInProgress, 100)
	if err != nil {
		r.logger.Printf("stuck reaper: list in_progress: %v", err)
		return
	}
	for _, ord := range orders {
		if ord.UpdatedAt.After(cutoff) {
			continue
		}
		r.logger.Printf("stuck reaper: FLAG order=%s in_progress stuck (driver=%s, age=%s) — requires manual review",
			ord.ID, safeDriverID(ord.DriverID), now.Sub(ord.UpdatedAt).Round(time.Second))
	}
}

// reapAwaitingPayment flags orders stuck in awaiting_payment.
// Never auto-completes without payment confirmation — financial integrity.
func (r *StuckOrderReaper) reapAwaitingPayment(ctx context.Context, now time.Time) {
	cutoff := now.Add(-r.awaitingPaymentFlagThreshold)
	orders, err := r.orderRepo.ListByStatus(ctx, orderdomain.StatusAwaitingPayment, 100)
	if err != nil {
		r.logger.Printf("stuck reaper: list awaiting_payment: %v", err)
		return
	}
	for _, ord := range orders {
		if ord.UpdatedAt.After(cutoff) {
			continue
		}
		r.logger.Printf("stuck reaper: FLAG order=%s awaiting_payment stuck (age=%s) — requires manual review",
			ord.ID, now.Sub(ord.UpdatedAt).Round(time.Second))
	}
}

func safeDriverID(drvID *string) string {
	if drvID == nil {
		return ""
	}
	return *drvID
}
