package order

import "context"

type Repository interface {
	Create(ctx context.Context, order *Order) error
	Update(ctx context.Context, order *Order) error
	GetByID(ctx context.Context, id string) (*Order, error)
}
