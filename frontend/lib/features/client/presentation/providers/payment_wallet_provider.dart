import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/payment_repository.dart';
import '../../domain/entities/payment_wallet.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  return PaymentRepository(
    apiClient: AppConstants.skipAuth && (token == null || token.isEmpty)
        ? const NoOpApiClient()
        : platform_api.createPlatformApiClient(),
    accessToken: token,
  );
});

final paymentWalletProvider =
    StateNotifierProvider<PaymentWalletNotifier, PaymentWalletState>((ref) {
  return PaymentWalletNotifier(ref.watch(paymentRepositoryProvider));
});

class PaymentWalletState {
  const PaymentWalletState({
    this.wallet,
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final PaymentWallet? wallet;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;

  bool get isEmpty => wallet != null && wallet!.cards.isEmpty;

  PaymentWalletState copyWith({
    PaymentWallet? wallet,
    bool? isLoading,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PaymentWalletState(
      wallet: wallet ?? this.wallet,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PaymentWalletNotifier extends StateNotifier<PaymentWalletState> {
  PaymentWalletNotifier(this._repository)
      : super(const PaymentWalletState(isLoading: true)) {
    unawaited(load());
  }

  final PaymentRepository _repository;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final wallet = await _repository.getWallet();
      state = state.copyWith(wallet: wallet, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> addCard(AddPaymentCardCommand command) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.addCard(command);
      final wallet = await _repository.getWallet();
      state = state.copyWith(
        wallet: wallet,
        isSubmitting: false,
      );
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _messageFor(error),
      );
      rethrow;
    }
  }

  Future<void> setDefaultCard(String cardId) async {
    final wallet = state.wallet;
    if (wallet == null) return;

    state = state.copyWith(
      wallet: wallet.copyWith(
        cards: wallet.cards
            .map((card) => card.copyWith(isDefault: card.id == cardId))
            .toList(),
      ),
      clearError: true,
    );

    try {
      await _repository.setDefaultCard(cardId);
      final updated = await _repository.getWallet();
      state = state.copyWith(wallet: updated);
    } catch (error) {
      state = state.copyWith(errorMessage: _messageFor(error));
      unawaited(load());
    }
  }

  Future<void> deleteCard(String cardId) async {
    final wallet = state.wallet;
    if (wallet == null) return;
    if (wallet.cards.isEmpty) return;

    final removedIndex = wallet.cards.indexWhere((card) => card.id == cardId);
    if (removedIndex < 0) return;
    final removed = wallet.cards[removedIndex];
    final remaining = wallet.cards.where((card) => card.id != cardId).toList();
    final normalized = removed.isDefault && remaining.isNotEmpty
        ? [
            remaining.first.copyWith(isDefault: true),
            ...remaining.skip(1).map((card) => card.copyWith(isDefault: false)),
          ]
        : remaining;

    state = state.copyWith(
      wallet: wallet.copyWith(cards: normalized),
      clearError: true,
    );

    try {
      await _repository.deleteCard(cardId);
      final updated = await _repository.getWallet();
      state = state.copyWith(wallet: updated);
    } catch (error) {
      state = state.copyWith(errorMessage: _messageFor(error));
      unawaited(load());
    }
  }

  Future<void> applyPromocode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(errorMessage: 'Введите промокод');
      return;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final promo = await _repository.applyPromocode(trimmed);
      final wallet =
          state.wallet ?? const PaymentWallet(cards: [], payments: []);
      state = state.copyWith(
        wallet: wallet.copyWith(promocode: promo),
        isSubmitting: false,
      );
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  String _messageFor(Object error) {
    final text = error.toString();
    if (text.contains('invalid promocode')) return 'Промокод не найден';
    if (text.contains('invalid card number')) return 'Проверьте номер карты';
    if (text.contains('card is expired')) return 'Срок карты истек';
    if (text.contains('Нет подключения')) return 'Нет подключения к интернету';
    return 'Не удалось обновить способы оплаты';
  }
}
