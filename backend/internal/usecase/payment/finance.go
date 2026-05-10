package payment

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"

	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	pricingdomain "evik/backend/internal/domain/pricing"
)

type PricingService interface {
	CalculatePrice(ctx context.Context, input pricingdomain.CalculatePriceInput) (*pricingdomain.PriceCalculation, error)
}

type PaymentProvider interface {
	CreatePayment(ctx context.Context, req ProviderPaymentRequest) (*ProviderPaymentResponse, error)
	CreatePayout(ctx context.Context, req ProviderPayoutRequest) (*ProviderPayoutResponse, error)
}

type ProviderPaymentRequest struct {
	Amount         int64
	Currency       string
	Description    string
	IdempotencyKey string
	Metadata       map[string]string
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
	clock             Clock
	idGen             IDGenerator
	holdSeconds       int
	minimumWithdrawal int64
	webhookSecret     string
}

func NewFinanceUseCase(repo paymentdomain.Repository, orderRepo orderdomain.Repository, pricingService PricingService, provider PaymentProvider, clock Clock, idGen IDGenerator, holdSeconds int, minimumWithdrawal int64, webhookSecret string) *FinanceUseCase {
	return &FinanceUseCase{
		repo:              repo,
		orderRepo:         orderRepo,
		pricingService:    pricingService,
		provider:          provider,
		clock:             clock,
		idGen:             idGen,
		holdSeconds:       holdSeconds,
		minimumWithdrawal: minimumWithdrawal,
		webhookSecret:     webhookSecret,
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
		return nil, errors.New("order does not belong to user")
	}
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
		Amount:         calculation.TotalPrice,
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
		Amount:         calculation.TotalPrice,
		Currency:       paymentdomain.CurrencyRUB,
		Description:    "Tow Truck order " + orderID,
		IdempotencyKey: idempotencyKey,
		Metadata: map[string]string{
			"purpose":  string(paymentdomain.PaymentPurposeOrder),
			"order_id": orderID,
			"user_id":  userID,
		},
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

func (uc *FinanceUseCase) HandleYooKassaWebhook(ctx context.Context, payload []byte, signature string) error {
	if uc.webhookSecret != "" && !validSignature(payload, signature, uc.webhookSecret) {
		return errors.New("invalid webhook signature")
	}
	var event struct {
		Type   string `json:"type"`
		Event  string `json:"event"`
		Object struct {
			ID       string            `json:"id"`
			Status   string            `json:"status"`
			Paid     bool              `json:"paid"`
			Metadata map[string]string `json:"metadata"`
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
	p, err := uc.repo.UpdatePaymentFromProvider(ctx, event.Object.ID, event.Object.Status, event.Object.Paid || event.Object.Status == string(paymentdomain.PaymentStatusSucceeded))
	if err != nil {
		return err
	}
	if p.Purpose == paymentdomain.PaymentPurposeSubscription && p.Status == paymentdomain.PaymentStatusSucceeded {
		if err := uc.repo.ActivateSubscriptionByPayment(ctx, p.ID); err != nil {
			return err
		}
	}
	return uc.repo.MarkWebhookProcessed(ctx, eventID)
}

func (uc *FinanceUseCase) CompleteOrderFinancially(ctx context.Context, orderID string) error {
	return uc.repo.CompleteOrderFinancially(ctx, orderID, "complete_order:"+orderID, uc.holdSeconds)
}

func (uc *FinanceUseCase) ReleasePendingBalances(ctx context.Context, limit int) (int, error) {
	if limit <= 0 {
		limit = 100
	}
	return uc.repo.ReleasePendingBalances(ctx, limit)
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
		_ = uc.repo.MarkPayoutFailed(ctx, created.ID, err.Error())
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
	amount := subscriptionAmount(planID)
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

func (uc *FinanceUseCase) MinimumWithdrawal() int64 {
	return uc.minimumWithdrawal
}

func validSignature(payload []byte, header, secret string) bool {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(header))
}

func subscriptionAmount(planID string) int64 {
	switch planID {
	case "pro_month":
		return 199000
	default:
		return 99000
	}
}

func strPtr(v string) *string {
	return &v
}
