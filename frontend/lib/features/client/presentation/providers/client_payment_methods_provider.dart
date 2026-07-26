import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/features/client/domain/entities/payment_wallet.dart';
import 'payment_wallet_provider.dart';

final clientPaymentMethodsProvider = StateNotifierProvider<
    ClientPaymentMethodsNotifier, AsyncValue<List<PaymentCard>>>((ref) {
  return ClientPaymentMethodsNotifier(ref);
});

class ClientPaymentMethodsNotifier
    extends StateNotifier<AsyncValue<List<PaymentCard>>> {
  ClientPaymentMethodsNotifier(this._ref) : super(const AsyncValue.loading()) {
    unawaited(load());
  }

  final Ref _ref;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final wallet = await _ref.read(paymentRepositoryProvider).getWallet();
      if (!_disposed) state = AsyncValue.data(wallet.cards);
    } catch (error, stackTrace) {
      if (!_disposed) state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<String> addCard() async {
    final previous = state.valueOrNull ?? const <PaymentCard>[];
    state = const AsyncValue.loading();
    try {
      final init = await _ref.read(paymentRepositoryProvider).initAddCard();
      if (init.confirmationUrl.isEmpty) {
        throw StateError('Не удалось получить ссылку ЮKassa');
      }
      final opened = await launchUrl(
        Uri.parse(init.confirmationUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('Не удалось открыть страницу ЮKassa');
      }
      // Poll for the new card after the user returns from the YooKassa 3DS flow.
      // The backend receives a webhook and activates the card asynchronously.
      List<PaymentCard> cards = previous;
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          final wallet = await _ref.read(paymentRepositoryProvider).getWallet();
          cards = wallet.cards;
          final hasNewCard = cards.any(
            (c) => !previous.any((p) => p.id == c.id),
          );
          if (hasNewCard) {
            if (!_disposed) state = AsyncValue.data(cards);
            return init.paymentMethodId;
          }
        } catch (_) {
          // continue polling
        }
      }
      // Timeout — show whatever we got last
      if (!_disposed) state = AsyncValue.data(cards);
      return init.paymentMethodId;
    } catch (error, stackTrace) {
      if (!_disposed) state = AsyncValue.error(error, stackTrace);
      if (previous.isNotEmpty) {
        scheduleMicrotask(() {
          if (!_disposed) state = AsyncValue.data(previous);
        });
      }
      rethrow;
    }
  }

  Future<void> deleteCard(String id) async {
    final previous = state.valueOrNull ?? const <PaymentCard>[];
    state = AsyncValue.data(previous.where((card) => card.id != id).toList());
    try {
      await _ref.read(paymentRepositoryProvider).deleteCard(id);
      await load();
    } catch (error, stackTrace) {
      if (!_disposed) state = AsyncValue.error(error, stackTrace);
      scheduleMicrotask(() {
        if (!_disposed) state = AsyncValue.data(previous);
      });
      rethrow;
    }
  }

  Future<void> setDefault(String id) async {
    final previous = state.valueOrNull ?? const <PaymentCard>[];
    state = AsyncValue.data(
      previous.map((card) => card.copyWith(isDefault: card.id == id)).toList(),
    );
    try {
      await _ref.read(paymentRepositoryProvider).setDefaultCard(id);
      await load();
    } catch (error, stackTrace) {
      if (!_disposed) state = AsyncValue.error(error, stackTrace);
      scheduleMicrotask(() {
        if (!_disposed) state = AsyncValue.data(previous);
      });
      rethrow;
    }
  }
}
