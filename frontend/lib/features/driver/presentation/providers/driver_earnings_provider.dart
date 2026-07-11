import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_earnings_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_earnings.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_stats.dart';

final driverEarningsRepositoryProvider = Provider<DriverEarningsRepository>((ref) {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  return DriverEarningsRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: token,
  );
});

class DriverEarningsState {
  const DriverEarningsState({
    this.stats = EarningsStats.zero,
    this.isLoading = true,
    this.errorMessage,
    this.lastUpdated,
  });

  final EarningsStats stats;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastUpdated;

  DriverEarningsState copyWith({
    EarningsStats? stats,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastUpdated,
  }) {
    return DriverEarningsState(
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class DriverEarningsNotifier extends StateNotifier<DriverEarningsState> {
  DriverEarningsNotifier(this._repository)
      : super(const DriverEarningsState()) {
    unawaited(refresh());
  }

  final DriverEarningsRepository _repository;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final stats = await _repository.getEarnings();
      state = state.copyWith(
        stats: stats,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось загрузить данные о доходах: $error',
      );
    }
  }
}

final driverEarningsProvider =
    StateNotifierProvider<DriverEarningsNotifier, DriverEarningsState>((ref) {
  return DriverEarningsNotifier(ref.watch(driverEarningsRepositoryProvider));
});

final driverStatsFromEarningsProvider = Provider<DriverStats>((ref) {
  final earnings = ref.watch(driverEarningsProvider);
  final e = earnings.stats;
  return DriverStats(
    yesterday: const YesterdayStats(ordersCount: 0, earnings: 0, rating: 0),
    today: TodayStats(
      // TODO(B-48): DriverStats в рублях; убрать /100 при унификации
      ordersCount: e.todayOrders,
      earnings: e.todayAmount / 100.0,
    ),
    weekly: WeeklyStats(
      // TODO(B-48): DriverStats в рублях; убрать /100 при унификации
      totalEarnings: e.weekAmount / 100.0,
      weeklyChange: 0,
      ordersCount: e.weekOrders,
      averageOrder: e.weekOrders > 0
          // TODO(B-48): DriverStats в рублях; убрать /100 при унификации
          ? (e.weekAmount / e.weekOrders / 100.0)
          : 0,
      hoursWorked: 0,
      rating: e.ratingAverage,
      // не отображается на home screen (B-48: unused field)
      availableForWithdrawal: 0,
    ),
  );
});
