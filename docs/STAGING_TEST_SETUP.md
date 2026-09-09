# Тестовый контур EVIK на Render

`render.staging.yaml` создаёт отдельный backend, Redis и PostgreSQL для
интеграционных проверок. Production-сервис `evik-backend` этот blueprint не
меняет.

## Что включено

- `APP_ENV=staging`;
- `S3_STUB_MODE=true` — документы не уходят в реальное хранилище;
- `YOOKASSA_STUB_MODE=true` — реальные платежи не создаются;
- выплаты остаются отключены;
- фиксированный OTP для тестового входа: `123456`;
- `DRIVER_GATE_BYPASS=false`, поэтому водителя нужно одобрить через админку;
- отдельные staging PostgreSQL и Redis.

## Как создать сервис

В Render выберите **New → Blueprint**, укажите репозиторий EVIK и blueprint
`render.staging.yaml`. После создания сохраните сгенерированный
`ADMIN_PASSWORD` в менеджере паролей Render.

Ожидаемый backend URL:

```text
https://evik-backend-staging.onrender.com
```

Для мобильного debug-запуска используйте:

```bash
cd frontend
flutter run \
  --dart-define=EVIK_API_BASE_URL=https://evik-backend-staging.onrender.com \
  --dart-define=EVIK_WS_URL=wss://evik-backend-staging.onrender.com/ws/orders
```

Staging не предназначен для реальных пользователей, настоящих документов,
платежей или production-данных.
