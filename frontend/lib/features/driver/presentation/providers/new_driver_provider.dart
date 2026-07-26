import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/repository_impl/http_driver_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/active_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/available_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_stats.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_earnings_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_realtime_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';

final httpDriverRepositoryProvider = Provider<HttpDriverRepository>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  return HttpDriverRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
    accessTokenProvider: () => ref.read(authProvider).accessToken,
  );
});

class DriverState {
  DriverState({
    required this.workState,
    required List<AvailableOrder> availableOrders,
    this.activeOrder,
    required this.stats,
    this.isLoading = false,
    this.error,
  }) : availableOrders = List.unmodifiable(availableOrders);

  final DriverWorkState workState;
  final List<AvailableOrder> availableOrders;
  final ActiveOrder? activeOrder;
  final DriverStats stats;
  final bool isLoading;
  final String? error;

  DriverState copyWith({
    DriverWorkState? workState,
    List<AvailableOrder>? availableOrders,
    ActiveOrder? activeOrder,
    bool clearActiveOrder = false,
    DriverStats? stats,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return DriverState(
      workState: workState ?? this.workState,
      availableOrders: List.unmodifiable(
        availableOrders ?? this.availableOrders,
      ),
      activeOrder: clearActiveOrder ? null : activeOrder ?? this.activeOrder,
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class DriverNotifier extends StateNotifier<DriverState> {
  DriverNotifier({
    required HttpDriverRepository driverRepository,
    required Ref ref,
  })  : _driverRepository = driverRepository,
        _ref = ref,
        super(DriverState(
          workState: DriverWorkState.offline,
          availableOrders: const <AvailableOrder>[],
          stats: const DriverStats(
            yesterday: YesterdayStats(
              ordersCount: 0,
              earnings: 0,
              rating: 0,
            ),
            today: TodayStats(
              ordersCount: 0,
              earnings: 0,
            ),
            weekly: WeeklyStats(
              totalEarnings: 0,
              weeklyChange: 0,
              ordersCount: 0,
              averageOrder: 0,
              hoursWorked: 0,
              rating: 0,
              availableForWithdrawal: 0,
            ),
          ),
        )) {
    unawaited(_initializeDriver());
    _startPeriodicRefresh();
    _startOfferListener();
  }

  final HttpDriverRepository _driverRepository;
  final Ref _ref;
  Timer? _refreshTimer;
  Timer? _paymentPollTimer;
  StreamSubscription<OrderUpdate>? _wsSubscription;
  final Random _random = Random();

  String? get _currentDriverId {
    final userId = _ref.read(authProvider).user?.id;
    if (userId != null && userId.isNotEmpty) return userId;
    return null;
  }

  Future<void> _initializeDriver() async {
    final driverId = _currentDriverId;
    if (driverId == null) return;

    try {
      final profile = await _driverRepository.getDriver(driverId);
      var nextWorkState = profile?.isOnline == true
          ? DriverWorkState.online
          : DriverWorkState.offline;

      ActiveOrder? activeOrder;
      try {
        final activeOrderMap = await _driverRepository.getActiveOrder(driverId);
        activeOrder = activeOrderFromBackend(activeOrderMap);
        nextWorkState =
            activeOrder.status == ActiveOrderStatus.drivingToDestination
                ? DriverWorkState.navigatingToDropoff
                : DriverWorkState.hasActiveOrder;
      } catch (_) {
        activeOrder = null;
      }

      final stats = await _loadStats(driverId);
      if (!mounted) return;

      state = state.copyWith(
        workState: nextWorkState,
        activeOrder: activeOrder,
        clearActiveOrder: activeOrder == null,
        stats: stats,
        isLoading: false,
        clearError: true,
      );

      if (nextWorkState == DriverWorkState.online) {
        final token = _ref.read(authProvider).accessToken;
        if (token == null || token.isEmpty) {
          state = state.copyWith(error: 'Ошибка авторизации: нет токена');
          return;
        }
        final realtime = _ref.read(driverRealTimeProvider.notifier);
        await realtime.connectAsDriver(driverId, accessToken: token);
        await realtime.goOnline();
        await _loadCurrentOffer();
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Не удалось загрузить данные водителя: $error',
      );
    }
  }

  Future<void> goOnline({double? lat, double? lng}) async {
    final driverId = _currentDriverId;
    if (driverId == null || state.workState.hasActiveOrder) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _driverRepository.updateDriverStatus(
        driverId: driverId,
        isOnline: true,
        lat: lat,
        lng: lng,
      );

      // Подключаем WS: регистрируем водителя в Hub, шлём локацию
      final token = _ref.read(authProvider).accessToken;
      if (token == null || token.isEmpty) {
        state = state.copyWith(error: 'Ошибка авторизации: нет токена');
        return;
      }
      final realtime = _ref.read(driverRealTimeProvider.notifier);
      await realtime.connectAsDriver(driverId, accessToken: token);
      await realtime.goOnline();

      state = state.copyWith(
        workState: DriverWorkState.online,
        isLoading: false,
      );
      await _loadCurrentOffer();
    } catch (error) {
      state = state.copyWith(
        workState: DriverWorkState.online,
        isLoading: false,
      );
    }
  }

  Future<void> goOffline() async {
    final driverId = _currentDriverId;
    if (driverId == null || state.workState.hasActiveOrder) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _driverRepository.updateDriverStatus(
        driverId: driverId,
        isOnline: false,
        lat: null,
        lng: null,
      );

      // Отключаем WS: останавливаем локацию, закрываем линию
      final realtime = _ref.read(driverRealTimeProvider.notifier);
      await realtime.goOffline();

      state = state.copyWith(
        workState: DriverWorkState.offline,
        availableOrders: const <AvailableOrder>[],
        clearActiveOrder: true,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Не удалось уйти с линии: $error',
      );
    }
  }

  Future<void> acceptOrder(String orderId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final order = await _driverRepository.acceptOrder(orderId);
      state = state.copyWith(
        workState: DriverWorkState.hasActiveOrder,
        activeOrder: activeOrderFromBackend(order),
        availableOrders: const <AvailableOrder>[],
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Не удалось принять заказ: $error',
      );
    }
  }

  Future<void> declineOrder(String orderId) async {
    await _driverRepository.declineOffer(orderId);
    state = state.copyWith(
      availableOrders: const <AvailableOrder>[],
    );
    unawaited(_loadCurrentOffer());
  }

  void _startOfferListener() {
    _wsSubscription?.cancel();
    final realTimeService = _ref.read(realTimeLocationServiceProvider);
    _wsSubscription = realTimeService.orderUpdateStream.listen((update) {
      if (!mounted) return;
      if (update.status == OrderUpdateType.offerAssigned) {
        final rawPayload = update.rawPayload;
        if (rawPayload != null) {
          final expiresAtStr = rawPayload['expires_at']?.toString();
          DateTime? expiresAt;
          if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
            expiresAt = DateTime.tryParse(expiresAtStr)?.toUtc();
          }
          if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) return;
          final order = availableOrderFromOffer(rawPayload, update.orderId);
          state = state.copyWith(
            availableOrders: order.id.isNotEmpty ? [order] : const <AvailableOrder>[],
          );
        }
      }
    });
  }

  Future<void> arrivedAtClient() async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _updateOrderStatus('arrived');
      if (!mounted) return;
      state = state.copyWith(
        activeOrder:
            activeOrder.copyWith(status: ActiveOrderStatus.arrivedAtClient),
        isLoading: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> startDrivingToDestination() async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _updateOrderStatus('in_progress');
      if (!mounted) return;
      state = state.copyWith(
        workState: DriverWorkState.navigatingToDropoff,
        activeOrder: activeOrder.copyWith(
          status: ActiveOrderStatus.drivingToDestination,
        ),
        isLoading: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> completeOrder() async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final orderRepository = _ref.read(orderRepositoryProvider);
      final priceKopecks = (activeOrder.price * 100).round();
      await orderRepository.finalizeOrder(activeOrder.id, priceKopecks);
      if (!mounted) return;
      state = state.copyWith(
        workState: DriverWorkState.waitingForPayment,
        isLoading: false,
      );
      _startPaymentPolling(activeOrder.id);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  void _startPaymentPolling(String orderId) {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) {
        _paymentPollTimer?.cancel();
        return;
      }
      try {
        final orderRepository = _ref.read(orderRepositoryProvider);
        final order = await orderRepository.getOrder(orderId);
        if (!mounted || order == null) return;
        if (order.status == OrderStatus.completed) {
          _paymentPollTimer?.cancel();
          state = state.copyWith(
            workState: DriverWorkState.online,
            clearActiveOrder: true,
          );
          await _loadCurrentOffer();
        }
      } catch (_) {
        // continue polling
      }
    });
  }

  Future<void> _updateOrderStatus(String status) async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;
    try {
      await _driverRepository.updateOrderStatus(
        orderId: activeOrder.id,
        status: status,
      );
    } catch (error) {
      state = state.copyWith(error: 'Не удалось обновить заказ: $error');
      rethrow;
    }
  }

  Future<void> _loadCurrentOffer() async {
    try {
      final offerMap = await _driverRepository.getCurrentOffer();
      if (offerMap == null) {
        state = state.copyWith(
          availableOrders: const <AvailableOrder>[],
        );
        return;
      }
      final orderId = offerMap['order_id']?.toString() ?? '';
      if (orderId.isEmpty) {
        state = state.copyWith(
          availableOrders: const <AvailableOrder>[],
        );
        return;
      }
      final expiresAtStr = offerMap['expires_at']?.toString();
      DateTime? expiresAt;
      if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
        expiresAt = DateTime.tryParse(expiresAtStr)?.toUtc();
      }
      if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
        state = state.copyWith(
          availableOrders: const <AvailableOrder>[],
        );
        return;
      }
      final order = availableOrderFromOffer(offerMap, orderId);
      state = state.copyWith(
        availableOrders: order.id.isNotEmpty ? [order] : const <AvailableOrder>[],
      );
    } catch (error) {
      // Polling errors are expected (network flakiness) — don't spam the UI.
    }
  }

  Future<DriverStats> _loadStats(String driverId) async {
    return _ref.read(driverStatsFromEarningsProvider);
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (state.workState == DriverWorkState.online) {
        unawaited(_loadCurrentOffer());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _paymentPollTimer?.cancel();
    _wsSubscription?.cancel();
    super.dispose();
  }
}

final newDriverProvider =
    StateNotifierProvider<DriverNotifier, DriverState>((ref) {
  return DriverNotifier(
    driverRepository: ref.watch(httpDriverRepositoryProvider),
    ref: ref,
  );
});
