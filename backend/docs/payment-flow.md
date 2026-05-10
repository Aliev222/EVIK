# Tow Truck Marketplace Finance

Currency is RUB. API amounts are integer kopecks. PostgreSQL stores financial balances as `NUMERIC(12,2)` and repository helpers convert kopecks to RUB.

## Rules

- Backend calculates all totals from order coordinates and tariffs.
- Flutter sends only `order_id` in URL and `payment_method` in JSON.
- Driver balances are changed only through `wallet_transactions`.
- Critical balance changes run in DB transactions and lock `driver_wallets` rows with `FOR UPDATE`.
- Idempotency is enforced with `payments.idempotency_key`, `wallet_transactions.idempotency_key`, `refunds.idempotency_key`, and `payment_webhooks.id`.
- Card numbers and CVV are not stored by the marketplace finance flow. YooKassa receives payment data through hosted confirmation.

## Card Order Flow

1. Client calls `POST /api/v1/orders/{order_id}/payments` with `{"payment_method":"card"}`.
2. Backend recalculates the price, creates a YooKassa payment with `Idempotence-Key`, saves `payments`, and returns `confirmation_url`.
3. YooKassa posts `POST /api/v1/webhooks/yookassa`.
4. Backend stores the webhook event, updates `payments.status`, and ignores duplicate events.
5. When order status becomes `completed`, `CompleteOrderFinancially` runs.
6. Commission is 15%. Driver amount first repays `debt_balance`; the remaining amount is credited to `pending_balance` with `wallet_transactions.type=order_income`.
7. `ReleasePendingBalancesJob` runs every minute and moves eligible pending income to available balance after `FINANCE_PENDING_HOLD_SECONDS`.
8. Driver requests payout manually. After provider success, `available_balance` is debited with `wallet_transactions.type=payout`.
9. Current YooKassa payout integration is explicitly sandbox-only: `YOOKASSA_PAYOUT_MODE=sandbox` returns a local mock provider payout id. `live` mode fails closed until separate card/SBP/bank_account payloads are implemented and certified.

## Cash Order Flow

1. Client pays driver directly.
2. Backend completes the order financially after order completion.
3. Commission is credited to `driver_wallets.debt_balance`.
4. A `wallet_transactions.type=cash_commission_debt` row is created.
5. Next card order automatically repays debt before new driver income is added to pending balance.

## Driver Subscription Flow

1. Driver calls `POST /api/v1/driver/subscription/payment`.
2. Backend creates YooKassa payment with purpose `subscription`.
3. Webhook marks `payments.status=succeeded`.
4. Backend activates the subscription. The full subscription amount is Tow Truck revenue and is not credited to the driver wallet.

## API Examples

Create order payment:

```http
POST /api/v1/orders/order_123/payments
Authorization: Bearer <client-token>
Content-Type: application/json

{"payment_method":"card"}
```

```json
{
  "payment": {
    "id": "pay_123",
    "order_id": "order_123",
    "provider": "yookassa",
    "payment_method": "card",
    "purpose": "order",
    "amount": 1000000,
    "currency": "RUB",
    "status": "pending",
    "confirmation_url": "https://yoomoney.ru/checkout/payments/..."
  }
}
```

YooKassa webhook:

```http
POST /api/v1/webhooks/yookassa
Content-Type: application/json
X-YooKassa-Signature: <hmac-sha256>

{"event":"payment.succeeded","object":{"id":"2abc","status":"succeeded","paid":true,"metadata":{"purpose":"order","order_id":"order_123"}}}
```

Driver wallet:

```http
GET /api/v1/driver/wallet
Authorization: Bearer <driver-token>
```

```json
{
  "available_balance": 850000,
  "pending_balance": 0,
  "debt_balance": 0,
  "currency": "RUB",
  "recent_transactions": [],
  "recent_payouts": []
}
```

Request payout:

```http
POST /api/v1/driver/payouts/request
Authorization: Bearer <driver-token>
Idempotency-Key: payout-request-uuid
Content-Type: application/json

{"amount":850000}
```

Create subscription payment:

```http
POST /api/v1/driver/subscription/payment
Authorization: Bearer <driver-token>
Content-Type: application/json

{"plan_id":"pro_month"}
```

Export report:

```http
POST /api/v1/admin/finance/export?type=wallet_transactions
Authorization: Bearer <admin-token>
```

Supported report types: `orders`, `payments`, `payouts`, `commissions`, `subscriptions`, `cash_debts`, `wallet_transactions`, `wallets`.

## YooKassa Notes

Payment creation uses YooKassa `/v3/payments`, Basic auth, and `Idempotence-Key`. Payouts are sandbox/mock in this build and are intentionally blocked in live mode until provider-specific card/SBP/bank_account payloads are added. Store YooKassa credentials only in environment variables.
