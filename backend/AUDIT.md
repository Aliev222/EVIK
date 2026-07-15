# B-06.4: Освобождение водителя — операции вне транзакции

| ID | Файл(ы) | Суть | Приоритет |
|----|----------|------|-----------|
| B-06.4 | `cancel_order.go:37`, `update_status.go:48`, `finance.go:325/402/420` | Освобождение водителя (ReleaseOrder) вызывается ВНЕ транзакции со сменой статуса заказа. Сбой между ними → заказ в терминальном статусе, водитель навсегда busy с `current_order_id` на мёртвый заказ → не может принять новый. | high |

## Решение
Обернуть 5 мест в execTx (как сделали приём в B-06.1):
1. `cancel_order.go:37` — `orderRepo.Update` + `driverRepo.ReleaseOrder`
2. `update_status.go:48` — `orderRepo.Update` + `driverRepo.ReleaseOrder`
3. `finance.go:325` — `orderRepo.Update` + `driverRepo.ReleaseOrder` (HandleProviderWebhook)
4. `finance.go:402` — `orderRepo.Update` + `driverRepo.ReleaseOrder` (ConfirmOrderPayment cash)
5. `finance.go:420` — `orderRepo.Update` + `driverRepo.ReleaseOrder` (ConfirmOrderPayment card)
