import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/api_client.dart';
import '../../domain/entities/user.dart';

// New auth provider using our Go backend instead of Firebase
final newAuthProvider = StateNotifierProvider<NewAuthNotifier, NewAuthState>((ref) {
  return NewAuthNotifier();
});

final currentUserProviderNew = Provider<User?>((ref) {
  return ref.watch(newAuthProvider.select((state) => state.user));
});

class NewAuthState {
  const NewAuthState({
    this.user,
    this.accessToken,
    this.isLoading = false,
    this.errorMessage,
    this.phoneNumber,
    this.pendingFullName,
    this.pendingRole,
    this.verificationId,
    this.codeSentAt,
    this.isSmsSent = false,
  });

  final User? user;
  final String? accessToken;
  final bool isLoading;
  final String? errorMessage;
  final String? phoneNumber;
  final String? pendingFullName;
  final UserRole? pendingRole;
  final String? verificationId;
  final DateTime? codeSentAt;
  final bool isSmsSent;

  bool get isAuthenticated => user != null;
  bool get canVerifyCode => isSmsSent && verificationId != null;

  NewAuthState copyWith({
    User? user,
    String? accessToken,
    bool clearAccessToken = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    String? phoneNumber,
    String? pendingFullName,
    UserRole? pendingRole,
    String? verificationId,
    bool clearVerificationId = false,
    DateTime? codeSentAt,
    bool clearCodeSentAt = false,
    bool clearPendingAuth = false,
    bool? isSmsSent,
  }) {
    return NewAuthState(
      user: user ?? this.user,
      accessToken: clearAccessToken ? null : accessToken ?? this.accessToken,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      phoneNumber: clearPendingAuth ? null : phoneNumber ?? this.phoneNumber,
      pendingFullName: clearPendingAuth ? null : pendingFullName ?? this.pendingFullName,
      pendingRole: clearPendingAuth ? null : pendingRole ?? this.pendingRole,
      verificationId: clearPendingAuth || clearVerificationId ? null : verificationId ?? this.verificationId,
      codeSentAt: clearPendingAuth || clearCodeSentAt ? null : codeSentAt ?? this.codeSentAt,
      isSmsSent: clearPendingAuth ? false : isSmsSent ?? this.isSmsSent,
    );
  }
}

class NewAuthNotifier extends StateNotifier<NewAuthState> {
  NewAuthNotifier() : super(const NewAuthState()) {
    _initializeApiClient();
  }

  final _apiClient = ApiClient();

  Future<void> _initializeApiClient() async {
    await _apiClient.init();
    if (_apiClient.isAuthenticated) {
      await _loadCurrentUser();
    }
  }

  // Step 1: Send SMS verification code
  Future<void> sendSmsCode(
    String rawPhoneNumber,
    String fullName, {
    UserRole role = UserRole.client,
  }) async {
    final normalizedPhone = _normalizePhone(rawPhoneNumber);
    if (normalizedPhone == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Введите корректный номер телефона.',
      );
      return;
    }

    final trimmedName = fullName.trim();
    if (trimmedName.length < 2) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Введите имя не короче 2 символов.',
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      phoneNumber: normalizedPhone,
      pendingFullName: trimmedName,
      pendingRole: role,
    );

    try {
      final response = await _apiClient.post('/auth/send-sms', {
        'phone': normalizedPhone,
      });

      state = state.copyWith(
        isLoading: false,
        verificationId: response['verification_id'],
        codeSentAt: DateTime.now(),
        isSmsSent: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e, 'Не удалось отправить SMS код'),
      );
    }
  }

  // Step 2: Verify SMS code and complete authentication
  Future<void> verifySmsCode(String code) async {
    final sanitizedCode = code.replaceAll(RegExp(r'[^\d]'), '');
    if (sanitizedCode.length != 4) { // Assuming 4-digit code
      state = state.copyWith(errorMessage: 'Введите 4 цифры из SMS.');
      return;
    }

    final verificationId = state.verificationId;
    final phoneNumber = state.phoneNumber;
    final fullName = state.pendingFullName;
    final role = state.pendingRole;

    if (verificationId == null || phoneNumber == null || fullName == null || role == null) {
      state = state.copyWith(
        errorMessage: 'Сессия подтверждения истекла. Запросите код заново.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await _apiClient.post('/auth/verify-sms', {
        'verification_id': verificationId,
        'code': sanitizedCode,
        'phone': phoneNumber,
        'full_name': fullName,
        'role': role.name,
      });

      // Save tokens using ApiClient
      await _apiClient.setTokens(
        response['access_token'],
        response['refresh_token'],
      );

      // Create user object
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromMap(userData);

      state = state.copyWith(
        user: user,
        accessToken: response['access_token'],
        isLoading: false,
        clearError: true,
        clearPendingAuth: true,
      );

    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e, 'Неверный код подтверждения'),
      );
    }
  }

  // Resend SMS code
  Future<void> resendSmsCode() async {
    final phoneNumber = state.phoneNumber;
    final fullName = state.pendingFullName;
    final role = state.pendingRole;

    if (phoneNumber == null || fullName == null || role == null) {
      state = state.copyWith(
        errorMessage: 'Сессия подтверждения истекла. Запросите код заново.',
      );
      return;
    }

    await sendSmsCode(phoneNumber, fullName, role: role);
  }

  // Load current user from API
  Future<void> _loadCurrentUser() async {
    try {
      state = state.copyWith(isLoading: true);
      final response = await _apiClient.get('/auth/me');
      final user = User.fromMap(response['user'] as Map<String, dynamic>);

      state = state.copyWith(
        user: user,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      // If loading user fails, clear auth state
      await signOut();
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _apiClient.clearTokens();
    state = state.copyWith(
      user: null,
      clearAccessToken: true,
      clearPendingAuth: true,
      clearError: true,
      isLoading: false,
    );
  }

  // Reset auth flow
  void resetAuth() {
    state = state.copyWith(
      isLoading: false,
      clearError: true,
      clearPendingAuth: true,
    );
  }

  // Update user role
  Future<void> updateUserRole(UserRole role) async {
    final currentUser = state.user;
    if (currentUser == null) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await _apiClient.put('/auth/role', {
        'role': role.name,
      });

      final updatedUser = User.fromMap(response['user'] as Map<String, dynamic>);

      state = state.copyWith(
        user: updatedUser,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e, 'Не удалось обновить роль'),
      );
    }
  }

  String? _normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;

    if (digits.length == 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
      return '+7${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '+7$digits';
    }
    if (digits.length > 10 && input.trim().startsWith('+')) {
      return '+$digits';
    }
    return null;
  }

  String _getErrorMessage(dynamic error, String fallback) {
    if (error is ApiClientException) {
      switch (error.statusCode) {
        case 400:
          return 'Неверный формат данных';
        case 401:
          return 'Неверный код подтверждения';
        case 429:
          return 'Слишком много попыток. Попробуйте позже';
        case 500:
          return 'Ошибка сервера. Попробуйте позже';
        default:
          return fallback;
      }
    }
    return fallback;
  }
}