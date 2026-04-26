import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repository_impl/http_driver_repository.dart';
import '../../domain/entities/active_order.dart';
import '../../domain/entities/available_order.dart';
import '../../domain/entities/driver_stats.dart';
import '../../domain/entities/driver_work_state.dart';

final httpDriverRepositoryProvider = Provider<HttpDriverRepository>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  return HttpDriverRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
  );
});

class DriverState {
  const DriverState({
    required this.workState,
    required this.availableOrders,
    this.activeOrder,
    required this.stats,
    this.isLoading = false,
    this.error,
  });

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
      availableOrders: availableOrders ?? this.availableOrders,
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
        super(const DriverState(
          workState: DriverWorkState.offline,
          availableOrders: <AvailableOrder>[],
          stats: DriverStats.mock,
        )) {
    unawaited(_initializeDriver());
    _startPeriodicRefresh();
  }

  final HttpDriverRepository _driverRepository;
  final Ref _ref;
  Timer? _refreshTimer;
  final Random _random = Random();

  String? get _currentDriverId => _ref.read(authProvider).user?.id;

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

      state = state.copyWith(
        workState: nextWorkState,
        activeOrder: activeOrder,
        clearActiveOrder: activeOrder == null,
        stats: await _loadStats(driverId),
        isLoading: false,
        clearError: true,
      );

      if (nextWorkState == DriverWorkState.online) {
        await _loadAvailableOrders();
      }
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Не удалось загрузить данные водителя: $error',
      );
    }
  }

  Future<void> goOnline() async {
    final driverId = _currentDriverId;
    if (driverId == null || state.workState.hasActiveOrder) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _driverRepository.updateDriverStatus(
        driverId: driverId,
        isOnline: true,
        lat: 55.7558 + (_random.nextDouble() - 0.5) * 0.01,
        lng: 37.6176 + (_random.nextDouble() - 0.5) * 0.01,
      );
      state = state.copyWith(
        workState: DriverWorkState.online,
        isLoading: false,
      );
      await _loadAvailableOrders();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Не удалось выйти на линию: $error',
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
        lat: 55.7558,
        lng: 37.6176,
      );
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
    state = state.copyWith(
      availableOrders:
          state.availableOrders.where((order) => order.id != orderId).toList(),
    );
  }

  Future<void> arrivedAtClient() async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;

    await _updateOrderStatus('arrived');
    state = state.copyWith(
      activeOrder:
          activeOrder.copyWith(status: ActiveOrderStatus.arrivedAtClient),
    );
  }

  Future<void> startDrivingToDestination() async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;

    await _updateOrderStatus('in_progress');
    state = state.copyWith(
      workState: DriverWorkState.navigatingToDropoff,
      activeOrder:
          activeOrder.copyWith(status: ActiveOrderStatus.drivingToDestination),
    );
  }

  Future<void> completeOrder() async {
    final activeOrder = state.activeOrder;
    if (activeOrder == null) return;

    await _updateOrderStatus('completed');
    state = state.copyWith(
      workState: DriverWorkState.online,
      clearActiveOrder: true,
    );
    await _loadAvailableOrders();
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

  Future<void> _loadAvailableOrders() async {
    try {
      final orders = await _driverRepository.getAvailableOrders();
      state = state.copyWith(
        availableOrders: orders.map(availableOrderFromBackend).toList(),
      );
    } catch (error) {
      state = state.copyWith(error: 'Не удалось загрузить заказы: $error');
    }
  }

  Future<DriverStats> _loadStats(String driverId) async {
    final orders = await _driverRepository.getDriverOrders(driverId);
    final completed = orders
        .where((order) => order['status']?.toString() == 'completed')
        .length;
    final todayEarnings = completed * 2500.0;
    return DriverStats(
      yesterday:
          const YesterdayStats(ordersCount: 4, earnings: 6200, rating: 4.9),
      today: TodayStats(ordersCount: completed, earnings: todayEarnings),
      weekly: WeeklyStats(
        totalEarnings: todayEarnings + 18400,
        weeklyChange: 12,
        ordersCount: completed + 12,
        averageOrder: 2500,
        hoursWorked: 28,
        rating: 4.9,
        availableForWithdrawal: todayEarnings + 18400,
      ),
    );
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (state.workState == DriverWorkState.online) {
        unawaited(_loadAvailableOrders());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
