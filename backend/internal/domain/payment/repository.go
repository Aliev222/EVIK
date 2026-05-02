package payment

import "context"

type Repository interface {
	ListMethods(ctx context.Context, userID string) ([]PaymentMethod, error)
	AddMethod(ctx context.Context, method PaymentMethod) error
	SetDefaultMethod(ctx context.Context, userID string, methodID string) (*PaymentMethod, error)
	DeleteMethod(ctx context.Context, userID string, methodID string) error
	ListTransactions(ctx context.Context, userID string, limit int) ([]PaymentTransaction, error)
	CreateTransaction(ctx context.Context, transaction *PaymentTransaction) error
}
