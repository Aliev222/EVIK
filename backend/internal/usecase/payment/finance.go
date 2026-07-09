package payment

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"strconv"
	"strings"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	pricingdomain "evik/backend/internal/domain/pricing"
	"evik/backend/internal/domain/settings"
)

// Provider-facing sentinel errors. The container's provider adapter translates
// infrastructure transport errors into these so HTTP handlers can map them to
// accurate status codes (503/502/401) instead of a blanket 400.
var (
	// ErrProviderNotConfigured: the payment provider has no usable credentials.
	ErrProviderNotConfigured = errors.New("payment provider is not configured")
	// ErrProviderUnavailable: a network/transport failure reaching the provider.
	ErrProviderUnavailable = errors.New("payment provider is unavailable")
	// ErrProviderUnauthorized: the provider rejected our credentials.
	ErrProviderUnauthorized = errors.New("payment provider rejected credentials")
	// ErrOrderNotOwned: the caller does not own the order they are paying for.
	ErrOrderNotOwned = errors.New("order does not belong to user")
)

type Clock interface {
	Now() time.Time
}

type IDGenerator interface {
	NewID() string
}

type PricingService interface {
	CalculatePrice(ctx context.Context, input pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error)
}

type PaymentProvider interface {
	CreatePayment(ctx context.Context, req ProviderPaymentRequest) (*ProviderPaymentResponse, error)
	GetPayment(ctx context.Context, id string) (*ProviderPaymentResponse, error)
	CreatePayout(ctx context.Context, req ProviderPayoutRequest) (*ProviderPayoutResponse, error)
}

type ProviderPaymentRequest struct {
	Amount         int64
	Currency       string
	Description    string
	IdempotencyKey string
	Metadata       map[string]string
	Capture        bool
	SaveMethod     bool
}

type ProviderPaymentResponse struct {
	ID              string
	Status          string
	ConfirmationURL string
	Paid            bool
}

type ProviderPayoutRequest struct {
	Amount              int64
	Currency            string
	ProviderRecipientID string
	Description         string
	IdempotencyKey      string
}

type ProviderPayoutResponse struct {
	ID     string
	Status string
}

type FinanceUseCase struct {
	repo              paymentdomain.Repository
	orderRepo         orderdomain.Repository
	pricingService    PricingService
	provider          PaymentProvider
	settingsRepo      settings.Repository
	clock             Clock
	idGen             IDGenerator
	holdSeconds       int
	minimumWithdrawal int64
}

type DriverSubscriptionStatus struct {
	Status          string     `json:"status"`
	Plan            *string    `json:"plan"`
	Amount          int64      `json:"amount"`
	Currency        string     `json:"currency"`
	PeriodEnd       *time.Time `json:"period_end"`
	EndsAt          *time.Time `json:"ends_at"`
	DaysLeft        int        `json:"days_left"`
	CanAcceptOrders bool       `json:"can_accept_orders"`
}

func NewFinanceUseCase(repo paymentdomain.Repository, orderRepo orderdomain.Repository, pricingService PricingService, provider PaymentProvider, settingsRepo settings.Repository, clock Clock, idGen IDGenerator, holdSeconds int, minimumWithdrawal int64) *FinanceUseCase {
	return &FinanceUseCase{
		repo:              repo,
		orderRepo:         orderRepo,
		pricingService:    pricingService,
		provider:          provider,
		settingsRepo:      settingsRepo,
		clock:             clock,
		idGen:             idGen,
		holdSeconds:       holdSeconds,
		minimumWithdrawal: minimumWithdrawal,
	}
}

func (uc *FinanceUseCase) CreateOrderPayment(ctx context.Context, userID, orderID string, method paymentdomain.PaymentMethodType) (*paymentdomain.Payment, error) {
	if method != paymentdomain.PaymentMethodCard && method != paymentdomain.PaymentMethodCash {
		return nil, paymentdomain.ErrValidationFailed
	}
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if ord.UserID != userID {
		return nil, ErrOrderNotOwned
	}
	// Use the stored PriceTotal (which already includes cross-city surcharge
	// from accept_order.go) as the payment amount. Fall back to a fresh
	// calculation only when PriceTotal is zero (legacy orders).
	amount := ord.PriceTotal
	if amount <= 0 {
		calculation, err := uc.pricingService.CalculatePrice(ctx, pricingdomain.CalculatePriceInput{
			OrderID:      ord.ID,
			PickupLat:    ord.Pickup.Lat,
			PickupLng:    ord.Pickup.Lng,
			DropoffLat:   ord.Dropoff.Lat,
			DropoffLng:   ord.Dropoff.Lng,
			TowTruckType: ord.TowTruckType,
		})
		if err != nil {
			return nil, err
		}
		amount = calculation.TotalPrice
	}
	now := uc.clock.Now()
	idempotencyKey := "order_payment:" + orderID + ":" + string(method)
	p := &paymentdomain.Payment{
		ID:             uc.idGen.NewID(),
		OrderID:        &orderID,
		DriverID:       ord.DriverID,
		UserID:         userID,
		Provider:       paymentdomain.ProviderYooKassa,
		PaymentMethod:  method,
		Purpose:        paymentdomain.PaymentPurposeOrder,
		Amount:         amount,
		Currency:       paymentdomain.CurrencyRUB,
		Status:         paymentdomain.PaymentStatusPending,
		IdempotencyKey: idempotencyKey,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if method == paymentdomain.PaymentMethodCash {
		p.Status = paymentdomain.PaymentStatusSucceeded
		p.ProviderPaymentID = strPtr("cash:" + orderID)
		p.PaidAt = &now
		return uc.repo.CreateOrderPayment(ctx, p)
	}
	providerPayment, err := uc.provider.CreatePayment(ctx, ProviderPaymentRequest{
		Amount:         amount,
		Currency:       paymentdomain.CurrencyRUB,
		Description:    "Tow Truck order " + orderID,
		IdempotencyKey: idempotencyKey,
		Metadata: map[string]string{
			"purpose":  string(paymentdomain.PaymentPurposeOrder),
			"order_id": orderID,
			"user_id":  userID,
		},
		Capture: true,
	})
	if err != nil {
		return nil, err
	}
	p.ProviderPaymentID = &providerPayment.ID
	p.Status = paymentdomain.PaymentStatus(providerPayment.Status)
	p.ConfirmationURL = &providerPayment.ConfirmationURL
	if providerPayment.Paid {
		p.Status = paymentdomain.PaymentStatusSucceeded
		p.PaidAt = &now
	}
	return uc.repo.CreateOrderPayment(ctx, p)
}

func (uc *FinanceUseCase) SaveClientPaymentMethod(ctx context.Context, clientID string) (*paymentdomain.AddCardInit, error) {
	now := uc.clock.Now()
	methodID := uc.idGen.NewID()
	idempotencyKey := "client_payment_method:" + methodID
	providerPayment, err := uc.provider.CreatePayment(ctx, ProviderPaymentRequest{
		Amount:         100,
		Currency:       paymentdomain.CurrencyRUB,
		Description:    "Tow Truck card binding",
		IdempotencyKey: idempotencyKey,
		Metadata: map[string]string{
			"purpose":           string(paymentdomain.PaymentPurposeCardBinding),
			"user_id":           clientID,
			"payment_method_id": methodID,
		},
		Capture:    false,
		SaveMethod: true,
	})
	if err != nil {
		return nil, err
	}
	payment := &paymentdomain.Payment{
		ID:                uc.idGen.NewID(),
		UserID:            clientID,
		Provider:          paymentdomain.ProviderYooKassa,
		ProviderPaymentID: &providerPayment.ID,
		PaymentMethod:     paymentdomain.PaymentMethodCard,
		Purpose:           paymentdomain.PaymentPurposeCardBinding,
		Amount:            100,
		Currency:          paymentdomain.CurrencyRUB,
		Status:            paymentdomain.PaymentStatus(providerPayment.Status),
		ConfirmationURL:   &providerPayment.ConfirmationURL,
		IdempotencyKey:    idempotencyKey,
		CreatedAt:         now,
		UpdatedAt:         now,
	}
	method := paymentdomain.PaymentMethod{
		ID:                methodID,
		UserID:            clientID,
		Provider:          paymentdomain.ProviderYooKassa,
		ProviderPaymentID: &providerPayment.ID,
		Brand:             paymentdomain.CardBrandUnknown,
		Last4:             "0000",
		Status:            "pending",
		CreatedAt:         now,
	}
	return uc.repo.CreatePendingPaymentMethod(ctx, payment, method)
}

func (uc *FinanceUseCase) HandleYooKassaWebhook(ctx context.Context, payload []byte) error {
	var event struct {
		Type   string `json:"type"`
		Event  string `json:"event"`
		Object struct {
			ID            string            `json:"id"`
			Status        string            `json:"status"`
			Paid          bool              `json:"paid"`
			Metadata      map[string]string `json:"metadata"`
			PaymentMethod struct {
				ID    string `json:"id"`
				Saved bool   `json:"saved"`
				Title string `json:"title"`
				Card  struct {
					Last4       string `json:"last4"`
					ExpiryMonth string `json:"expiry_month"`
					ExpiryYear  string `json:"expiry_year"`
					CardType    string `json:"card_type"`
				} `json:"card"`
			} `json:"payment_method"`
		} `json:"object"`
	}
	if err := json.Unmarshal(payload, &event); err != nil {
		return err
	}
	eventType := event.Event
	if eventType == "" {
		eventType = event.Type
	}
	eventID := eventType + ":" + event.Object.ID
	inserted, err := uc.repo.StoreWebhook(ctx, eventID, string(paymentdomain.ProviderYooKassa), eventType, payload)
	if err != nil || !inserted {
		return err
	}

	status := event.Object.Status
	paid := event.Object.Paid || event.Object.Status == string(paymentdomain.PaymentStatusSucceeded)

	apiResp, err := uc.provider.GetPayment(ctx, event.Object.ID)
	if err != nil {
		return fmt.Errorf("failed to verify payment with provider: %w", err)
	}
	status = apiResp.Status
	paid = apiResp.Paid

	p, err := uc.repo.UpdatePaymentFromProvider(ctx, event.Object.ID, status, paid)
	if err != nil {
		return err
	}
	if p.Purpose == paymentdomain.PaymentPurposeSubscription && p.Status == paymentdomain.PaymentStatusSucceeded {
		if err := uc.repo.ActivateSubscriptionByPayment(ctx, p.ID); err != nil {
			return err
		}
	}
	if p.Purpose == paymentdomain.PaymentPurposeCardBinding &&
		event.Object.PaymentMethod.Saved &&
		event.Object.PaymentMethod.ID != "" {
		expMonth, err := strconv.Atoi(event.Object.PaymentMethod.Card.ExpiryMonth)
		if err != nil {
			return fmt.Errorf("parse card exp month %q: %w", event.Object.PaymentMethod.Card.ExpiryMonth, err)
		}
		expYear, err := strconv.Atoi(event.Object.PaymentMethod.Card.ExpiryYear)
		if err != nil {
			return fmt.Errorf("parse card exp year %q: %w", event.Object.PaymentMethod.Card.ExpiryYear, err)
		}
		if err := uc.repo.ActivatePaymentMethodFromProvider(
			ctx,
			event.Object.ID,
			event.Object.PaymentMethod.ID,
			event.Object.PaymentMethod.Card.CardType,
			event.Object.PaymentMethod.Card.Last4,
			expMonth,
			expYear,
			event.Object.PaymentMethod.Title,
		); err != nil {
			return err
		}
	}
	if p.Purpose == paymentdomain.PaymentPurposeOrder && p.Status == paymentdomain.PaymentStatusSucceeded && p.OrderID != nil {
		orderID := *p.OrderID
		if finErr := uc.CompleteOrderFinancially(ctx, orderID); finErr != nil {
			return finErr
		}
		ord, ordErr := uc.orderRepo.GetByID(ctx, orderID)
		if ordErr != nil {
			return ordErr
		}
		now := uc.clock.Now()
		ord.Status = orderdomain.StatusCompleted
		ord.UpdatedAt = now
		if updErr := uc.orderRepo.Update(ctx, ord); updErr != nil {
			return updErr
		}
	}
	return uc.repo.MarkWebhookProcessed(ctx, eventID)
}

const fallbackCommissionPercent = 15

func (uc *FinanceUseCase) commissionPercent(ctx context.Context) int {
	list, err := uc.settingsRepo.List(ctx)
	if err != nil {
		log.Printf("WARN: settings unavailable, commission fallback %d%%: %v", fallbackCommissionPercent, err)
		return fallbackCommissionPercent
	}
	for _, s := range list {
		if s.Key != "commission_percent" {
			continue
		}
		str, ok := s.Value.(string)
		if !ok {
			log.Printf("WARN: commission_percent not a string (%T), fallback %d%%", s.Value, fallbackCommissionPercent)
			return fallbackCommissionPercent
		}
		f, err := strconv.ParseFloat(str, 64)
		if err != nil || f < 0 || f > 100 {
			log.Printf("WARN: invalid commission_percent %q, fallback %d%%", str, fallbackCommissionPercent)
			return fallbackCommissionPercent
		}
		if f != float64(int(f)) {
			log.Printf("WARN: fractional commission_percent %.2f truncated to %d", f, int(f))
		}
		return int(f)
	}
	log.Printf("WARN: commission_percent not found in settings, fallback %d%%", fallbackCommissionPercent)
	return fallbackCommissionPercent
}

func (uc *FinanceUseCase) CompleteOrderFinancially(ctx context.Context, orderID string) error {
	pct := uc.commissionPercent(ctx)
	return uc.repo.CompleteOrderFinancially(ctx, orderID, "complete_order:"+orderID, uc.holdSeconds, pct)
}

// ConfirmOrderPayment processes the client's payment confirmation for an order
// in awaiting_payment status. For cash orders it immediately completes finances
// and transitions to completed. For card orders it creates a YooKassa payment
// with Capture: true; if paid at creation the order completes right away,
// otherwise a confirmation_url is returned for 3DS.
func (uc *FinanceUseCase) ConfirmOrderPayment(ctx context.Context, userID, orderID string) (*paymentdomain.Payment, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if ord.UserID != userID {
		return nil, ErrOrderNotOwned
	}
	if ord.Status != orderdomain.StatusAwaitingPayment {
		return nil, orderdomain.ErrInvalidTransition
	}

	paymentMethod := ord.PaymentMethod
	if paymentMethod == "" {
		paymentMethod = "cash"
	}

	if paymentMethod == "cash" {
		if err := uc.CompleteOrderFinancially(ctx, orderID); err != nil {
			return nil, err
		}
		ord.Status = orderdomain.StatusCompleted
		ord.UpdatedAt = uc.clock.Now()
		if err := uc.orderRepo.Update(ctx, ord); err != nil {
			return nil, err
		}
		return nil, nil
	}

	payment, err := uc.CreateOrderPayment(ctx, userID, orderID, paymentdomain.PaymentMethodCard)
	if err != nil {
		return nil, err
	}
	if payment.Status == paymentdomain.PaymentStatusSucceeded {
		if err := uc.CompleteOrderFinancially(ctx, orderID); err != nil {
			return nil, err
		}
		ord.Status = orderdomain.StatusCompleted
		ord.UpdatedAt = uc.clock.Now()
		if err := uc.orderRepo.Update(ctx, ord); err != nil {
			return nil, err
		}
	}
	return payment, nil
}

// UpdateOrderPaymentMethod changes the payment method on an order that is
// still in awaiting_payment status. Only the order owner may perform this
// change. Valid methods are "cash" and "card".
func (uc *FinanceUseCase) UpdateOrderPaymentMethod(ctx context.Context, userID, orderID string, method paymentdomain.PaymentMethodType) error {
	if method != paymentdomain.PaymentMethodCard && method != paymentdomain.PaymentMethodCash {
		return paymentdomain.ErrValidationFailed
	}
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	if ord.UserID != userID {
		return ErrOrderNotOwned
	}
	if ord.Status != orderdomain.StatusAwaitingPayment {
		return orderdomain.ErrInvalidTransition
	}
	ord.PaymentMethod = string(method)
	ord.UpdatedAt = uc.clock.Now()
	return uc.orderRepo.Update(ctx, ord)
}

func (uc *FinanceUseCase) ReleasePendingBalances(ctx context.Context, limit int) (int, error) {
	if limit <= 0 {
		limit = 100
	}
	transactions, err := uc.repo.ListReleasablePendingTransactions(ctx, limit)
	if err != nil {
		return 0, err
	}
	count := 0
	var failed []string
	for _, transaction := range transactions {
		if err := uc.repo.MarkTransactionReleased(ctx, transaction.ID); err != nil {
			failed = append(failed, fmt.Sprintf("%s: %v", transaction.ID, err))
			continue
		}
		count++
	}
	if len(failed) > 0 {
		return count, fmt.Errorf("release pending balances failed for %d transactions: %s", len(failed), strings.Join(failed, "; "))
	}
	return count, nil
}

func (uc *FinanceUseCase) RequestDriverPayout(ctx context.Context, driverID string, amount int64, idempotencyKey string) (*paymentdomain.Payout, error) {
	if amount <= 0 {
		return nil, paymentdomain.ErrInvalidAmount
	}
	methods, err := uc.repo.ListPayoutMethods(ctx, driverID)
	if err != nil {
		return nil, err
	}
	var method *paymentdomain.DriverPayoutMethod
	for i := range methods {
		if methods[i].IsDefault && methods[i].Status == "active" {
			method = &methods[i]
			break
		}
	}
	if method == nil {
		return nil, paymentdomain.ErrPayoutMethodNotFound
	}
	now := uc.clock.Now()
	if idempotencyKey == "" {
		idempotencyKey = fmt.Sprintf("payout:%s:%d:%d", driverID, amount, now.Unix())
	}
	payout := &paymentdomain.Payout{
		ID:        uc.idGen.NewID(),
		DriverID:  driverID,
		Provider:  paymentdomain.ProviderYooKassa,
		Amount:    amount,
		Currency:  paymentdomain.CurrencyRUB,
		Status:    paymentdomain.PayoutStatusCreated,
		CreatedAt: now,
		UpdatedAt: now,
	}
	created, err := uc.repo.CreatePayout(ctx, payout, idempotencyKey)
	if err != nil {
		return nil, err
	}
	if created.Status == paymentdomain.PayoutStatusPaid || created.ProviderPayoutID != nil {
		return created, nil
	}
	providerPayout, err := uc.provider.CreatePayout(ctx, ProviderPayoutRequest{
		Amount:              amount,
		Currency:            paymentdomain.CurrencyRUB,
		ProviderRecipientID: method.ProviderRecipientID,
		Description:         "Tow Truck driver payout",
		IdempotencyKey:      idempotencyKey,
	})
	if err != nil {
		if markErr := uc.repo.MarkPayoutFailed(ctx, created.ID, err.Error()); markErr != nil {
			log.Printf("CRITICAL: failed to mark payout %s as failed: %v (original error: %v)", created.ID, markErr, err)
		}
		return nil, err
	}
	if providerPayout.Status == string(paymentdomain.PayoutStatusPaid) || providerPayout.Status == "succeeded" {
		if err := uc.repo.MarkPayoutPaid(ctx, created.ID, providerPayout.ID, idempotencyKey); err != nil {
			return nil, err
		}
		created.Status = paymentdomain.PayoutStatusPaid
		created.ProviderPayoutID = &providerPayout.ID
	}
	return created, nil
}

func (uc *FinanceUseCase) CreateDriverSubscriptionPayment(ctx context.Context, driverID, planID string) (*paymentdomain.Payment, error) {
	amount, err := uc.subscriptionAmount(ctx, planID)
	if err != nil {
		return nil, err
	}
	now := uc.clock.Now()
	idempotencyKey := "subscription:" + driverID + ":" + planID + ":" + now.Format("2006-01")
	payment := &paymentdomain.Payment{
		ID:             uc.idGen.NewID(),
		DriverID:       &driverID,
		UserID:         driverID,
		Provider:       paymentdomain.ProviderYooKassa,
		PaymentMethod:  paymentdomain.PaymentMethodCard,
		Purpose:        paymentdomain.PaymentPurposeSubscription,
		Amount:         amount,
		Currency:       paymentdomain.CurrencyRUB,
		Status:         paymentdomain.PaymentStatusPending,
		IdempotencyKey: idempotencyKey,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	providerPayment, err := uc.provider.CreatePayment(ctx, ProviderPaymentRequest{
		Amount:         amount,
		Currency:       paymentdomain.CurrencyRUB,
		Description:    "Tow Truck driver subscription " + planID,
		IdempotencyKey: idempotencyKey,
		Metadata: map[string]string{
			"purpose":   string(paymentdomain.PaymentPurposeSubscription),
			"driver_id": driverID,
			"plan_id":   planID,
		},
		Capture: true,
	})
	if err != nil {
		return nil, err
	}
	payment.ProviderPaymentID = &providerPayment.ID
	payment.Status = paymentdomain.PaymentStatus(providerPayment.Status)
	payment.ConfirmationURL = &providerPayment.ConfirmationURL
	subscription := &paymentdomain.Subscription{
		ID:        uc.idGen.NewID(),
		DriverID:  driverID,
		PlanID:    planID,
		Amount:    amount,
		Currency:  paymentdomain.CurrencyRUB,
		Status:    paymentdomain.SubscriptionStatusPending,
		CreatedAt: now,
		UpdatedAt: now,
	}
	return uc.repo.CreateSubscriptionPayment(ctx, payment, subscription)
}

func (uc *FinanceUseCase) GetDriverSubscriptionStatus(ctx context.Context, driverID string) (*DriverSubscriptionStatus, error) {
	active, err := uc.repo.GetActiveDriverSubscription(ctx, driverID)
	if err != nil {
		return nil, err
	}
	if active != nil {
		return uc.subscriptionStatus(active, "active", true), nil
	}

	latest, err := uc.repo.GetLatestDriverSubscription(ctx, driverID)
	if err != nil {
		return nil, err
	}
	if latest == nil {
		return &DriverSubscriptionStatus{
			Status:          "none",
			Currency:        paymentdomain.CurrencyRUB,
			CanAcceptOrders: false,
		}, nil
	}
	if latest.EndsAt != nil && !latest.EndsAt.After(uc.clock.Now()) {
		return uc.subscriptionStatus(latest, "expired", false), nil
	}
	return &DriverSubscriptionStatus{
		Status:          "none",
		Currency:        paymentdomain.CurrencyRUB,
		CanAcceptOrders: false,
	}, nil
}

func (uc *FinanceUseCase) CreateRefund(ctx context.Context, paymentID string, amount int64, reason string) (*paymentdomain.Refund, error) {
	if amount <= 0 {
		return nil, paymentdomain.ErrInvalidAmount
	}
	now := uc.clock.Now()
	return uc.repo.CreateRefund(ctx, &paymentdomain.Refund{
		ID:             uc.idGen.NewID(),
		PaymentID:      paymentID,
		Amount:         amount,
		Currency:       paymentdomain.CurrencyRUB,
		Reason:         reason,
		Status:         paymentdomain.RefundStatusCreated,
		IdempotencyKey: fmt.Sprintf("refund:%s:%d:%s", paymentID, amount, reason),
		CreatedAt:      now,
		UpdatedAt:      now,
	})
}

// ApprovePayout marks a payout paid by admin decision. If the payout has
// an associated provider record, the provider is asked to execute the
// transfer first; otherwise the payout is closed manually (operator did
// a manual bank/SBP transfer). The provider call is skipped when the
// payout already has a provider_payout_id from a previous attempt.
func (uc *FinanceUseCase) ApprovePayout(ctx context.Context, payoutID, moderatorID string) (*paymentdomain.Payout, error) {
	payout, err := uc.repo.GetPayout(ctx, payoutID)
	if err != nil {
		return nil, err
	}
	if payout.Status == paymentdomain.PayoutStatusPaid {
		return payout, nil
	}
	providerPayoutID := ""
	if payout.ProviderPayoutID != nil {
		providerPayoutID = *payout.ProviderPayoutID
	}
	now := uc.clock.Now()
	return uc.repo.ApprovePayout(ctx, payoutID, moderatorID, providerPayoutID, now)
}

// RejectPayout cancels a payout that has not yet been paid. Reason must be
// supplied by the admin (validated by the handler).
func (uc *FinanceUseCase) RejectPayout(ctx context.Context, payoutID, moderatorID, reason string) (*paymentdomain.Payout, error) {
	if strings.TrimSpace(reason) == "" {
		return nil, paymentdomain.ErrValidationFailed
	}
	now := uc.clock.Now()
	return uc.repo.RejectPayout(ctx, payoutID, moderatorID, reason, now)
}

// ListAdminRefunds is a thin pass-through used by the admin handler.
func (uc *FinanceUseCase) ListAdminRefunds(ctx context.Context, filter paymentdomain.AdminRefundFilter) ([]paymentdomain.Refund, int64, error) {
	return uc.repo.ListAdminRefunds(ctx, filter)
}

func (uc *FinanceUseCase) MinimumWithdrawal() int64 {
	return uc.minimumWithdrawal
}

var subscriptionPriceHardcoded = map[string]int64{
	"pro_day":   50000,
	"pro_week":  250000,
	"pro_month": 900000,
}

var subscriptionPriceKeys = map[string]string{
	"pro_day":   "driver_subscription_daily_price",
	"pro_week":  "driver_subscription_weekly_price",
	"pro_month": "driver_subscription_monthly_price",
}

func (uc *FinanceUseCase) subscriptionAmount(ctx context.Context, planID string) (int64, error) {
	key, ok := subscriptionPriceKeys[planID]
	if !ok {
		return 0, fmt.Errorf("unknown subscription plan %q", planID)
	}
	settingsList, err := uc.settingsRepo.List(ctx)
	if err == nil {
		for _, s := range settingsList {
			if s.Key == key {
				switch v := s.Value.(type) {
				case float64:
					return int64(v), nil
				case string:
					n, err := strconv.ParseInt(v, 10, 64)
					if err == nil {
						return n, nil
					}
				}
			}
		}
	}

	hardcoded, ok := subscriptionPriceHardcoded[planID]
	if ok {
		log.Printf("WARN: %s not found in settings, using hardcoded price %d", key, hardcoded)
		return hardcoded, nil
	}

	return 0, fmt.Errorf("unknown subscription plan %q", planID)
}

func (uc *FinanceUseCase) subscriptionStatus(subscription *paymentdomain.Subscription, status string, canAcceptOrders bool) *DriverSubscriptionStatus {
	plan := subscription.PlanID
	daysLeft := 0
	if canAcceptOrders && subscription.EndsAt != nil {
		daysLeft = int(math.Ceil(subscription.EndsAt.Sub(uc.clock.Now()).Hours() / 24))
		if daysLeft < 0 {
			daysLeft = 0
		}
	}
	return &DriverSubscriptionStatus{
		Status:          status,
		Plan:            &plan,
		Amount:          subscription.Amount,
		Currency:        subscription.Currency,
		PeriodEnd:       subscription.EndsAt,
		EndsAt:          subscription.EndsAt,
		DaysLeft:        daysLeft,
		CanAcceptOrders: canAcceptOrders,
	}
}

func strPtr(v string) *string {
	return &v
}
