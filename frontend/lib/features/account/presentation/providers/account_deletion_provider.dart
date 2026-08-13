import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/account/data/account_repository.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

enum AccountDeletionStatus { idle, loading, conflict, error, success }

class AccountDeletionState {
  const AccountDeletionState({
    this.status = AccountDeletionStatus.idle,
    this.message,
  });

  final AccountDeletionStatus status;
  final String? message;

  bool get isLoading => status == AccountDeletionStatus.loading;

  AccountDeletionState copyWith({
    AccountDeletionStatus? status,
    String? message,
  }) {
    return AccountDeletionState(
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

class AccountDeletionNotifier extends StateNotifier<AccountDeletionState> {
  AccountDeletionNotifier(this._repository)
      : super(const AccountDeletionState());

  final AccountRepository _repository;

  Future<void> deleteAccount() async {
    if (state.isLoading) return;
    state = const AccountDeletionState(
      status: AccountDeletionStatus.loading,
    );
    try {
      await _repository.deleteAccount();
      state = const AccountDeletionState(status: AccountDeletionStatus.success);
    } on ApiClientException catch (error) {
      if (error.statusCode == 409) {
        state = AccountDeletionState(
          status: AccountDeletionStatus.conflict,
          message: error.message,
        );
        return;
      }
      state = AccountDeletionState(
        status: AccountDeletionStatus.error,
        message: error.message,
      );
    } catch (_) {
      state = const AccountDeletionState(
        status: AccountDeletionStatus.error,
        message: 'Не удалось удалить аккаунт. Попробуйте позже.',
      );
    }
  }

  void reset() => state = const AccountDeletionState();
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  return AccountRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
    accessTokenProvider: () => ref.read(authProvider).accessToken,
  );
});

final accountDeletionProvider =
    StateNotifierProvider<AccountDeletionNotifier, AccountDeletionState>((ref) {
  return AccountDeletionNotifier(ref.watch(accountRepositoryProvider));
});