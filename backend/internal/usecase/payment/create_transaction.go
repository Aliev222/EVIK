package payment

import (
	"context"
	"time"

	paymentdomain "evik/backend/internal/domain/payment"
)

type Clock interface {
	Now() time.Time
}

type IDGenerator interface {
	NewID() string
}

type CreateTransactionUseCase struct {
	repo      paymentdomain.Repository
	clock     Clock
	idGen     IDGenerator
}

func NewCreateTransactionUseCase(repo paymentdomain.Repository, clock Clock, idGen IDGenerator) *CreateTransactionUseCase {
	return &CreateTransactionUseCase{
		repo:  repo,
		clock: clock,
		idGen: idGen,
	}
}

func (uc *CreateTransactionUseCase) CreateTransaction(ctx context.Context, userID, orderID, title string, amount int64) (*paymentdomain.PaymentTransaction, error) {
	transaction := &paymentdomain.PaymentTransaction{
		ID:        uc.idGen.NewID(),
		UserID:    userID,
		OrderID:   orderID,
		Title:     title,
		Amount:    amount,
		Status:    "pending", // Start with pending status
		CreatedAt: uc.clock.Now(),
	}

	if err := uc.repo.CreateTransaction(ctx, transaction); err != nil {
		return nil, err
	}

	return transaction, nil
}