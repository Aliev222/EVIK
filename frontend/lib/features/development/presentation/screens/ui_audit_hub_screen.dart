import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/features/auth/presentation/auth_screen.dart';
import 'package:tow_truck_frontend/features/auth/presentation/screens/sms_verification_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_app_shell.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_history_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_home_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_profile_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_wallet_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/destination_location_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/driver_info_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/driver_rating_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/edit_order_route_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/order_completion_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/order_review_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/pickup_location_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/service_detail_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/tow_truck_selection_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/tracking_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/vehicle_selection_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/services_placeholder_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/driver_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/active_order_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_blocked_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_debt_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_documents_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_earnings_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_moderation_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_order_receipt_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_orders_history_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_profile_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_profile_setup_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_tax_profile_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/moderation_waiting_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/new_driver_home_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/document_camera_screen.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_onboarding.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/active_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_stats.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'package:tow_truck_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/shared/widgets/offline_sos_screen.dart';

/// Development-only navigation hub for visual QA on a physical device or
/// simulator. The entry point is protected in [main.dart] by a dart-define
/// and cannot be enabled in a release binary.
class UiAuditHubScreen extends StatelessWidget {
  const UiAuditHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        title: const Text('UI-аудит Авро'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Только для разработки',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Открывай экран, делай скриншот, возвращайся сюда. '
            'Режим не включается в release-сборках.',
          ),
          const SizedBox(height: 22),
          _Section(
            title: 'Клиент: разделы',
            children: [
              _AuditEntry(
                icon: Icons.person_outline_rounded,
                title: 'Выбор роли',
                subtitle: 'Первый запуск',
                onTap: () => _open(context, const RoleSelectionScreen()),
              ),
              _AuditEntry(
                icon: Icons.login_rounded,
                title: 'Вход',
                subtitle: 'Номер телефона и пароль',
                onTap: () => _open(context, const AuthScreen()),
              ),
              _AuditEntry(
                icon: Icons.sms_outlined,
                title: 'Подтверждение SMS',
                subtitle: 'Ввод одноразового кода',
                onTap: () => _open(context, const SmsVerificationScreen()),
              ),
              _AuditEntry(
                icon: Icons.home_outlined,
                title: 'Главная клиента',
                subtitle: 'Карта, услуги и нижняя навигация',
                onTap: () => _open(context, const ClientAppShell()),
              ),
              _AuditEntry(
                icon: Icons.map_outlined,
                title: 'Карта клиента',
                subtitle: 'Главный экран без нижней навигации',
                onTap: () => _open(context, const ClientHomeScreen()),
              ),
              _AuditEntry(
                icon: Icons.miscellaneous_services_outlined,
                title: 'Услуги клиента',
                subtitle: 'Заглушка каталога услуг',
                onTap: () => _open(context, const ServicesPlaceholderScreen()),
              ),
              _AuditEntry(
                icon: Icons.history_rounded,
                title: 'История клиента',
                subtitle: 'Прошлые заказы',
                onTap: () => _open(context, const ClientHistoryScreen()),
              ),
              _AuditEntry(
                icon: Icons.hourglass_top_rounded,
                title: 'История клиента: загрузка',
                subtitle: 'Настоящие skeleton-карточки',
                onTap: () => _open(
                    context,
                    const ClientHistoryScreen(
                        auditState: HistoryState.loading)),
              ),
              _AuditEntry(
                icon: Icons.inbox_outlined,
                title: 'История клиента: пусто',
                subtitle: 'Настоящее пустое состояние',
                onTap: () => _open(context,
                    const ClientHistoryScreen(auditState: HistoryState.empty)),
              ),
              _AuditEntry(
                icon: Icons.error_outline_rounded,
                title: 'История клиента: ошибка',
                subtitle: 'Настоящий экран ошибки и повтор',
                onTap: () => _open(context,
                    const ClientHistoryScreen(auditState: HistoryState.error)),
              ),
              _AuditEntry(
                icon: Icons.person_outline_rounded,
                title: 'Профиль клиента',
                subtitle: 'Данные и настройки',
                onTap: () => _open(context, const ClientProfileScreen()),
              ),
              _AuditEntry(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Кошелёк клиента',
                subtitle: 'Карты и способы оплаты',
                onTap: () => _open(context, const ClientWalletScreen()),
              ),
              _AuditEntry(
                icon: Icons.handshake_outlined,
                title: 'Карточка партнёрской услуги',
                subtitle: 'Детальный экран услуги',
                onTap: () => _open(
                  context,
                  const ServiceDetailScreen(
                    title: 'Выездной шиномонтаж',
                    subtitle: 'Помощь рядом с автомобилем',
                    description: 'Демонстрационный экран партнёрской услуги.',
                    icon: Icons.tire_repair_rounded,
                  ),
                ),
              ),
              _AuditEntry(
                icon: Icons.sos_rounded,
                title: 'SOS',
                subtitle: 'Экстренный сценарий без входа',
                onTap: () =>
                    _open(context, const OfflineSosScreen(isSosOnly: true)),
              ),
              _AuditEntry(
                  icon: Icons.location_on_outlined,
                  title: 'Точка А: loaded',
                  subtitle: 'Фикстура адреса забора',
                  onTap: () => _open(context, const PickupLocationScreen())),
              _AuditEntry(
                  icon: Icons.flag_outlined,
                  title: 'Точка Б: loaded',
                  subtitle: 'Фикстура адреса доставки',
                  onTap: () =>
                      _open(context, const DestinationLocationScreen())),
              _AuditEntry(
                  icon: Icons.directions_car_outlined,
                  title: 'Выбор автомобиля: loaded',
                  subtitle: 'Фикстура автомобиля клиента',
                  onTap: () => _open(context, const VehicleSelectionScreen())),
              _AuditEntry(
                  icon: Icons.local_shipping_outlined,
                  title: 'Выбор эвакуатора: loaded',
                  subtitle: 'Фикстура тарифа эвакуатора',
                  onTap: () => _open(context, const TowTruckSelectionScreen())),
              _AuditEntry(
                  icon: Icons.person_pin_circle_outlined,
                  title: 'Водитель найден: loaded',
                  subtitle: 'Фикстура назначенного водителя',
                  onTap: () => _open(context, const DriverInfoScreen())),
              _AuditEntry(
                  icon: Icons.route_outlined,
                  title: 'Трекинг: loaded',
                  subtitle: 'Фикстура активного заказа',
                  onTap: () => _open(context, const TrackingScreen(auditDemo: true))),
              _AuditEntry(
                  icon: Icons.star_outline_rounded,
                  title: 'Оценка водителя: loaded',
                  subtitle: 'Фикстура завершённого заказа',
                  onTap: () => _open(context, const DriverRatingScreen())),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Водитель: разделы',
            children: [
              _AuditEntry(
                icon: Icons.local_shipping_outlined,
                title: 'Главная водителя',
                subtitle: 'Смена, заказы и профиль',
                onTap: () => _open(context, const DriverScreen()),
              ),
              _AuditEntry(
                icon: Icons.home_work_outlined,
                title: 'Смена водителя',
                subtitle: 'Главная до принятия заказа',
                onTap: () => _open(context, const NewDriverHomeScreen()),
              ),
              _AuditEntry(
                icon: Icons.cloud_off_outlined,
                title: 'Смена: offline',
                subtitle: 'Нет активной смены',
                onTap: () => _open(
                    context,
                    NewDriverHomeScreen(
                        auditState: _driverHomeState(DriverWorkState.offline))),
              ),
              _AuditEntry(
                icon: Icons.sync_outlined,
                title: 'Смена: loading',
                subtitle: 'Загрузка состояния смены',
                onTap: () => _open(
                    context,
                    NewDriverHomeScreen(
                        auditState: _driverHomeState(DriverWorkState.offline,
                            isLoading: true))),
              ),
              _AuditEntry(
                icon: Icons.error_outline,
                title: 'Смена: error',
                subtitle: 'Ошибка загрузки заказов',
                onTap: () => _open(
                    context,
                    NewDriverHomeScreen(
                        auditState: _driverHomeState(DriverWorkState.offline,
                            error: 'Не удалось загрузить заказы'))),
              ),
              _AuditEntry(
                icon: Icons.inbox_outlined,
                title: 'Смена: доступных заказов нет',
                subtitle: 'Онлайн, но предложений пока нет',
                onTap: () => _open(
                    context,
                    NewDriverHomeScreen(
                        auditState: _driverHomeState(DriverWorkState.online))),
              ),
              _AuditEntry(
                icon: Icons.drive_eta_outlined,
                title: 'Активный заказ водителя',
                subtitle: 'Карта и действия в поездке',
                onTap: () => _open(context, const ActiveOrderScreen()),
              ),
              _AuditEntry(
                icon: Icons.directions_car_filled_outlined,
                title: 'Водитель: принял заказ',
                subtitle: 'Едет к клиенту',
                onTap: () => _open(
                    context,
                    ActiveOrderScreen(
                      auditState: _driverOrderState(
                        ActiveOrderStatus.drivingToClient,
                        DriverWorkState.hasActiveOrder,
                      ),
                    )),
              ),
              _AuditEntry(
                icon: Icons.location_on_outlined,
                title: 'Водитель: прибыл',
                subtitle: 'На месте у клиента',
                onTap: () => _open(
                    context,
                    ActiveOrderScreen(
                      auditState: _driverOrderState(
                        ActiveOrderStatus.arrivedAtClient,
                        DriverWorkState.hasActiveOrder,
                      ),
                    )),
              ),
              _AuditEntry(
                icon: Icons.local_shipping_outlined,
                title: 'Водитель: везёт автомобиль',
                subtitle: 'Едет к месту назначения',
                onTap: () => _open(
                    context,
                    ActiveOrderScreen(
                      auditState: _driverOrderState(
                        ActiveOrderStatus.drivingToDestination,
                        DriverWorkState.navigatingToDropoff,
                      ),
                    )),
              ),
              _AuditEntry(
                icon: Icons.credit_card_outlined,
                title: 'Водитель: ожидание оплаты',
                subtitle: 'Заказ завершён, оплата картой',
                onTap: () => _open(
                    context,
                    ActiveOrderScreen(
                      auditState: _driverOrderState(
                        ActiveOrderStatus.completed,
                        DriverWorkState.waitingForPayment,
                      ),
                    )),
              ),
              _AuditEntry(
                icon: Icons.task_alt_outlined,
                title: 'Водитель: оплата получена',
                subtitle: 'Финальное подтверждение',
                onTap: () => _open(
                    context,
                    ActiveOrderScreen(
                      auditState: _driverOrderState(
                        ActiveOrderStatus.completed,
                        DriverWorkState.paymentReceived,
                      ),
                    )),
              ),
              _AuditEntry(
                icon: Icons.history_outlined,
                title: 'История водителя',
                subtitle: 'Завершённые заказы',
                onTap: () => _open(context, const DriverOrdersHistoryScreen()),
              ),
              _AuditEntry(
                icon: Icons.hourglass_top_rounded,
                title: 'История водителя: загрузка',
                subtitle: 'Настоящие skeleton-карточки',
                onTap: () => _open(
                    context,
                    const DriverOrdersHistoryScreen(
                        auditState: DriverHistoryState.loading)),
              ),
              _AuditEntry(
                icon: Icons.inbox_outlined,
                title: 'История водителя: пусто',
                subtitle: 'Настоящее пустое состояние',
                onTap: () => _open(
                    context,
                    const DriverOrdersHistoryScreen(
                        auditState: DriverHistoryState.empty)),
              ),
              _AuditEntry(
                icon: Icons.error_outline_rounded,
                title: 'История водителя: ошибка',
                subtitle: 'Настоящий экран ошибки',
                onTap: () => _open(
                    context,
                    const DriverOrdersHistoryScreen(
                        auditState: DriverHistoryState.error)),
              ),
              _AuditEntry(
                  icon: Icons.camera_alt_outlined,
                  title: 'Камера документа: недоступна',
                  subtitle: 'Реальный экран с ошибкой разрешения/камеры',
                  onTap: () => _open(
                      context,
                      const DocumentCameraScreen(
                          type: DriverDocumentType.passport))),
              _AuditEntry(
                icon: Icons.account_balance_outlined,
                title: 'Доходы водителя',
                subtitle: 'Баланс и выплаты',
                onTap: () => _open(context, const DriverEarningsScreen()),
              ),
              _AuditEntry(
                icon: Icons.badge_outlined,
                title: 'Профиль водителя',
                subtitle: 'Автомобиль и настройки',
                onTap: () => _open(context, const DriverProfileScreen()),
              ),
              _AuditEntry(
                icon: Icons.description_outlined,
                title: 'Документы водителя',
                subtitle: 'Загрузка и проверка',
                onTap: () => _open(context, const DriverDocumentsScreen()),
              ),
              _AuditEntry(
                icon: Icons.edit_note_outlined,
                title: 'Настройка профиля водителя',
                subtitle: 'Первичное заполнение',
                onTap: () => _open(context, const DriverProfileSetupScreen()),
              ),
              _AuditEntry(
                icon: Icons.receipt_long_outlined,
                title: 'Налоговый профиль',
                subtitle: 'Данные самозанятого',
                onTap: () => _open(context, const DriverTaxProfileScreen()),
              ),
              _AuditEntry(
                icon: Icons.money_off_csred_outlined,
                title: 'Долг водителя',
                subtitle: 'Комиссия и погашение',
                onTap: () => _open(context, const DriverDebtScreen()),
              ),
              _AuditEntry(
                icon: Icons.receipt_outlined,
                title: 'Чек заказа водителя',
                subtitle: 'Детали расчёта по заказу',
                onTap: () => _open(
                  context,
                  const DriverOrderReceiptScreen(orderId: 'ui-audit-order'),
                ),
              ),
              _AuditEntry(
                icon: Icons.pause_circle_outline,
                title: 'Ожидание модерации',
                subtitle: 'Заявка отправлена',
                onTap: () => _open(context, const ModerationWaitingScreen()),
              ),
              _AuditEntry(
                icon: Icons.gpp_bad_outlined,
                title: 'Водитель заблокирован',
                subtitle: 'Состояние ограничения',
                onTap: () => _open(
                  context,
                  const DriverBlockedScreen(reason: 'Демонстрационная причина'),
                ),
              ),
              _AuditEntry(
                icon: Icons.rule_outlined,
                title: 'Статус модерации',
                subtitle: 'Заявка ещё не отправлена',
                onTap: () => _open(
                  context,
                  const DriverModerationScreen(showMissingState: true),
                ),
              ),
              _AuditEntry(
                icon: Icons.hourglass_top_rounded,
                title: 'Модерация: загрузка',
                subtitle: 'Проверяем статус документов',
                onTap: () => _open(
                  context,
                  const DriverModerationScreen(isLoading: true),
                ),
              ),
              _AuditEntry(
                icon: Icons.error_outline_rounded,
                title: 'Модерация: ошибка',
                subtitle: 'Не удалось загрузить статус',
                onTap: () => _open(
                  context,
                  const DriverModerationScreen(
                    errorMessage: 'Проверьте подключение к интернету.',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Заказ эвакуатора',
            children: [
              _AuditEntry(
                icon: Icons.location_on_outlined,
                title: '1. Точка А',
                subtitle: 'Где забрать автомобиль',
                onTap: () => context.push('/order/pickup'),
              ),
              _AuditEntry(
                icon: Icons.flag_outlined,
                title: '2. Точка Б',
                subtitle: 'Куда доставить автомобиль',
                onTap: () => context.push('/order/destination'),
              ),
              _AuditEntry(
                icon: Icons.directions_car_outlined,
                title: '3. Детали заказа',
                subtitle: 'Автомобиль, эвакуатор, цена и оплата',
                onTap: () => context.push('/order/vehicle'),
              ),
              _AuditEntry(
                icon: Icons.radar_rounded,
                title: '4. Поиск водителя',
                subtitle: 'Ожидание и отмена',
                onTap: () => context.push('/order/search'),
              ),
              _AuditEntry(
                icon: Icons.person_pin_circle_outlined,
                title: '5. Водитель найден',
                subtitle: 'Карточка и связь с водителем',
                onTap: () => context.push('/order/driver-info'),
              ),
              _AuditEntry(
                icon: Icons.route_outlined,
                title: '6. Трекинг заказа',
                subtitle: 'Карта, статусы и маршрут',
                onTap: () => context.push('/order/tracking'),
              ),
              _AuditEntry(
                icon: Icons.credit_card_outlined,
                title: '7. Подтверждение оплаты',
                subtitle: 'Оплата заказа',
                onTap: () => context.push('/order/payment-confirmation'),
              ),
              _AuditEntry(
                icon: Icons.star_outline_rounded,
                title: '8. Оценка водителя',
                subtitle: 'Отзыв после заказа',
                onTap: () => context.push('/order/rating'),
              ),
              _AuditEntry(
                icon: Icons.task_alt_outlined,
                title: '9. Заказ завершён',
                subtitle: 'Итоговый экран заказа',
                onTap: () => _open(context, const OrderCompletionScreen()),
              ),
              _AuditEntry(
                icon: Icons.list_alt_outlined,
                title: '10. Проверка заказа',
                subtitle: 'Экран подтверждения перед созданием',
                onTap: () => _open(
                  context,
                  const OrderReviewScreen(orderId: 'ui-audit-order'),
                ),
              ),
              _AuditEntry(
                icon: Icons.edit_location_alt_outlined,
                title: '11. Смена адреса',
                subtitle: 'Перерасчёт маршрута и цены',
                onTap: () => _open(
                  context,
                  EditOrderRouteScreen(
                    order: Order(
                      id: 'ui-audit-order',
                      clientId: 'ui-audit-client',
                      status: OrderStatus.onWay,
                      pickupLocation: const LocationModel(
                        lat: 42.9849,
                        lng: 47.5047,
                        address: 'проспект Расула Гамзатова, 12, Махачкала',
                      ),
                      dropoffLocation: const LocationModel(
                        lat: 42.9705,
                        lng: 47.4897,
                        address: 'улица Петра I, 97, Махачкала',
                      ),
                      vehicleType: VehicleType.light,
                      distance: 6.8,
                      estimatedPrice: 1900,
                      paymentMethod: PaymentMethod.card,
                      createdAt: DateTime(2026, 9, 4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _AuditEntry extends StatelessWidget {
  const _AuditEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AvroClientColors.accent),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

DriverState _driverOrderState(
  ActiveOrderStatus status,
  DriverWorkState workState,
) =>
    DriverState(
      workState: workState,
      availableOrders: const [],
      activeOrder: ActiveOrder(
        id: 'ui-audit-driver-order',
        clientName: 'Магомед Магомедов',
        clientPhone: '+7 999 123-45-67',
        vehicleModel: 'Toyota Camry',
        problemType: 'Не заводится',
        blockedWheelsCount: 2,
        pickupAddress: 'проспект Расула Гамзатова, 12',
        dropoffAddress: 'улица Петра I, 97',
        pickupLat: 42.9849,
        pickupLng: 47.5047,
        dropoffLat: 42.9705,
        dropoffLng: 47.4897,
        price: 1900,
        distanceToClient: 2.4,
        totalDistance: 6.8,
        estimatedMinutes: 18,
        acceptedAt: DateTime(2026, 9, 11, 14, 30),
        status: status,
        paymentMethod: PaymentMethod.card,
      ),
      stats: const DriverStats(
        yesterday: YesterdayStats(ordersCount: 4, earnings: 5400, rating: 4.9),
        today: TodayStats(ordersCount: 2, earnings: 2800),
        weekly: WeeklyStats(
          totalEarnings: 24600,
          weeklyChange: 12,
          ordersCount: 18,
          averageOrder: 1367,
          hoursWorked: 26,
          rating: 4.9,
          availableForWithdrawal: 9800,
        ),
      ),
    );

DriverState _driverHomeState(
  DriverWorkState workState, {
  bool isLoading = false,
  String? error,
}) =>
    DriverState(
      workState: workState,
      availableOrders: const [],
      isLoading: isLoading,
      error: error,
      stats: const DriverStats(
        yesterday: YesterdayStats(ordersCount: 4, earnings: 5400, rating: 4.9),
        today: TodayStats(ordersCount: 2, earnings: 2800),
        weekly: WeeklyStats(
          totalEarnings: 24600,
          weeklyChange: 12,
          ordersCount: 18,
          averageOrder: 1367,
          hoursWorked: 26,
          rating: 4.9,
          availableForWithdrawal: 9800,
        ),
      ),
    );
