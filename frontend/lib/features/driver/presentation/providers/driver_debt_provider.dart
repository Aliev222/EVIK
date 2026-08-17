import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/driver/data/repository/driver_wallet_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_wallet_provider.dart';

/// State for the «Из чего сложился долг» breakdown shown on DriverDebtScreen.
class DriverDebtState {
  const DriverDebtState({
    this.breakdown,
    this.isLoading = false,
    this.errorMessage,
  });

  final DriverDebtBreakdown? breakdown;
  final bool isLoading;
  final String? errorMessage;

  bool get hasData => breakdown != null;

  DriverDebtState copyWith({
    DriverDebtBreakdown? breakdown,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DriverDebtState(
      breakdown: breakdown ?? this.breakdown,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final driverDebtProvider =
    StateNotifierProvider<DriverDebtNotifier, DriverDebtState>((ref) {
  return DriverDebtNotifier(ref.watch(driverWalletRepositoryProvider));
});

class DriverDebtNotifier extends StateNotifier<DriverDebtState> {
  DriverDebtNotifier(this._repository)
      : super(const DriverDebtState(isLoading: true)) {
    unawaited(refresh());
  }

  final DriverWalletRepository _repository;

  Future<void> refresh() async {
    if (state.breakdown != null) {
      state = state.copyWith(isLoading: true, clearError: true);
    } else {
      state = const DriverDebtState(isLoading: true);
    }
    try {
      final breakdown = await _repository.getDebtBreakdown();
      state = state.copyWith(
        breakdown: breakdown,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось загрузить историю долга',
      );
    }
  }
}