import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_wallet_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';

final driverWalletRepositoryProvider = Provider<DriverWalletRepository>((ref) {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  return DriverWalletRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: token,
  );
});

final driverWalletProvider =
    StateNotifierProvider<DriverWalletNotifier, DriverWalletState>((ref) {
  return DriverWalletNotifier(ref.watch(driverWalletRepositoryProvider));
});

class DriverWalletState {
  const DriverWalletState({
    this.wallet,
    this.payoutMethods = const [],
    this.subscriptionStatus,
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.lastUpdated,
  });

  final DriverWallet? wallet;
  final List<DriverPayoutMethod> payoutMethods;
  final DriverSubscriptionStatus? subscriptionStatus;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;
  final DateTime? lastUpdated;

  bool get canWithdraw {
    final hasMethod = payoutMethods
        .any((method) => method.isDefault && method.status == 'active');
    return (wallet?.availableBalance ?? 0) > 0 && hasMethod && !isSubmitting;
  }

  DriverWalletState copyWith({
    DriverWallet? wallet,
    List<DriverPayoutMethod>? payoutMethods,
    DriverSubscriptionStatus? subscriptionStatus,
    bool? isLoading,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastUpdated,
  }) {
    return DriverWalletState(
      wallet: wallet ?? this.wallet,
      payoutMethods: payoutMethods ?? this.payoutMethods,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class DriverWalletNotifier extends StateNotifier<DriverWalletState> {
  DriverWalletNotifier(this._repository)
      : super(const DriverWalletState(isLoading: true)) {
    unawaited(refresh());
  }

  final DriverWalletRepository _repository;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final wallet = await _repository.getWallet();
      final methods = await _repository.getPayoutMethods();
      final subscription = await _repository.getSubscriptionStatus();
      state = state.copyWith(
        wallet: wallet,
        payoutMethods: methods,
        subscriptionStatus: subscription,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> requestFullPayout() async {
    final amount = state.wallet?.availableBalance ?? 0;
    if (amount <= 0) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.requestPayout(amount);
      final wallet = await _repository.getWallet();
      state = state.copyWith(
        wallet: wallet,
        isSubmitting: false,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _messageFor(error),
      );
      rethrow;
    }
  }

  Future<void> addPayoutMethod({
    required String type,
    required String providerRecipientId,
    required String maskedValue,
    required bool isDefault,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.addPayoutMethod(
        type: type,
        providerRecipientId: providerRecipientId,
        maskedValue: maskedValue,
        isDefault: isDefault,
      );
      final methods = await _repository.getPayoutMethods();
      state = state.copyWith(
        payoutMethods: methods,
        isSubmitting: false,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _messageFor(error),
      );
      rethrow;
    }
  }

  Future<String?> createSubscriptionPayment(String planId) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final url = await _repository.createSubscriptionPayment(planId);
      final subscription = await _repository.getSubscriptionStatus();
      state = state.copyWith(
        subscriptionStatus: subscription,
        isSubmitting: false,
      );
      return url;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _messageFor(error),
      );
      rethrow;
    }
  }

  String _messageFor(Object error) {
    final text = error.toString();
    if (text.contains('insufficient available balance')) {
      return 'Недостаточно средств для вывода';
    }
    if (text.contains('payout method not found')) {
      return 'Добавьте способ вывода';
    }
    if (text.contains('401')) return 'Нужно войти заново';
    if (text.contains('0:')) return 'Нет подключения к интернету';
    return 'Не удалось загрузить баланс';
  }
}
