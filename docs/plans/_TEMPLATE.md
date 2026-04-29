# <Feature name>

## Context
- Зачем: <бизнес-цель>
- Связь с текущей архитектурой: <какие провайдеры/коллекции затрагиваются>

## Non-goals
<что НЕ делаем в этом тикете — защита от scope creep>

## Data model changes
- Firestore: <новые/изменённые коллекции, поля, индексы>
- Dart models: <классы в lib/shared/models или features/*/domain>

## State machine impact
<если трогаем статусы заказа — диаграмма переходов>

## Implementation steps (для Sonnet)
1. [ ] Создать файлы...
2. [ ] Добавить провайдеры...
3. [ ] Реализовать UI...

## Critical Files
- frontend/lib/features/order/providers/client_order_provider.dart
- frontend/lib/core/constants/firestore_collections.dart
- frontend/lib/shared/models/order.dart

## Tests required
- Provider override test для новых провайдеров
- Widget test для новых экранов

## Open questions
<вопросы, на которые Sonnet должен ответить кодом или эскалировать>

## Implementation report (Sonnet)
- Отклонения от плана: 
- Что не сделано из плана и почему:
- Новые файлы:
- Follow-ups: