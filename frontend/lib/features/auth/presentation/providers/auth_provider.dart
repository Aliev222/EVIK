import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:tow_truck_frontend/core/bootstrap/app_bootstrap.dart';
import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/core/network/auth_retry_coordinator.dart';
import 'package:tow_truck_frontend/core/notifications/push_notification_service.dart';
import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/client_payment_methods_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/payment_wallet_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';

const _accessTokenKey = 'auth_access_token';
const _refreshTokenKey = 'auth_refresh_token';
const _userKey = 'auth_user';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(
    api: BackendAuthApi(
      apiClient: platform_api.createPlatformApiClient(),
    ),
    storage: ref.read(keyValueStorageProvider),
    ref: ref,
  );
  AuthRetryCoordinator.configure(
    refresh: notifier.refreshAccessToken,
    logout: notifier.signOut,
  );
  return notifier;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider.select((state) => state.user));
});

class AuthState {
  const AuthState({
    this.user,
    this.accessToken,
    this.isLoading = false,
    this.isRestoring = true,
    this.errorMessage,
    this.phoneNumber,
    this.pendingFullName,
    this.pendingRole,
    this.verificationId,
    this.forceResendingToken,
    this.codeSentAt,
  });

  final User? user;
  final String? accessToken;
  final bool isLoading;
  // True while restoring a persisted session at startup — router holds on a
  // splash until this flips to false, so a signed-in user never briefly sees
  // the auth screen.
  final bool isRestoring;
  final String? errorMessage;
  final String? phoneNumber;
  final String? pendingFullName;
  final UserRole? pendingRole;
  final String? verificationId;
  final int? forceResendingToken;
  final DateTime? codeSentAt;

  bool get isAuthenticated => user != null;
  bool get isCodeSent => phoneNumber != null && verificationId != null;

  AuthState copyWith({
    User? user,
    String? accessToken,
    bool clearAccessToken = false,
    bool? isLoading,
    bool? isRestoring,
    String? errorMessage,
    bool clearError = false,
    String? phoneNumber,
    String? pendingFullName,
    UserRole? pendingRole,
    String? verificationId,
    bool clearVerificationId = false,
    int? forceResendingToken,
    bool clearForceResendingToken = false,
    DateTime? codeSentAt,
    bool clearCodeSentAt = false,
    bool clearPendingAuth = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      accessToken: clearAccessToken ? null : accessToken ?? this.accessToken,
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      phoneNumber: clearPendingAuth ? null : phoneNumber ?? this.phoneNumber,
      pendingFullName:
          clearPendingAuth ? null : pendingFullName ?? this.pendingFullName,
      pendingRole: clearPendingAuth ? null : pendingRole ?? this.pendingRole,
      verificationId: clearPendingAuth || clearVerificationId
          ? null
          : verificationId ?? this.verificationId,
      forceResendingToken: clearPendingAuth || clearForceResendingToken
          ? null
          : forceResendingToken ?? this.forceResendingToken,
      codeSentAt: clearPendingAuth || clearCodeSentAt
          ? null
          : codeSentAt ?? this.codeSentAt,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required BackendAuthApi api,
    required KeyValueStorage storage,
    required Ref ref,
  })  : _api = api,
        _storage = storage,
        _ref = ref,
        super(const AuthState()) {
    _bindFcmTokenRefresh();
    unawaited(_restoreSession());
  }

  final BackendAuthApi _api;
  final KeyValueStorage _storage;
  final Ref _ref;
  StreamSubscription<String>? _fcmTokenRefreshSubscription;

  Future<void> signInWithPhone(
    String rawPhoneNumber,
    String fullName, {
    UserRole role = UserRole.client,
  }) async {
    final normalizedPhone = _normalizePhone(rawPhoneNumber);
    if (normalizedPhone == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Введите корректный номер телефона.',
      );
      return;
    }

    final trimmedName = fullName.trim();
    if (trimmedName.length < 2) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Введите имя не короче 2 символов.',
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      phoneNumber: normalizedPhone,
      pendingFullName: trimmedName,
      pendingRole: role,
      verificationId: 'backend-otp-pending',
      clearForceResendingToken: true,
      codeSentAt: DateTime.now(),
    );

    try {
      await _api.requestOtp(phone: normalizedPhone, role: role);
      state = state.copyWith(isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _loginErrorMessage(error),
        clearPendingAuth: true,
      );
    }
  }

  Future<void> verifySmsCode(String code) async {
    final sanitizedCode = code.replaceAll(RegExp(r'[^\d]'), '');
    if (sanitizedCode.length != 6) {
      state =
          state.copyWith(errorMessage: 'Введите 6 цифр из SMS.');
      return;
    }

    final phoneNumber = state.phoneNumber;
    final fullName = state.pendingFullName;
    final role = state.pendingRole;
    if (phoneNumber == null || fullName == null || role == null) {
      state = state.copyWith(
        errorMessage:
            'Сессия подтверждения истекла. Запросите код заново.',
      );
      return;
    }

    // Стандартный поток для продакшена
    final userID = _deriveUserID(phoneNumber);
    if (userID == null) {
      state = state.copyWith(
        errorMessage:
            'Не удалось сформировать идентификатор пользователя.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final authResult = await _api.verifyOtp(
        phone: phoneNumber,
        code: sanitizedCode,
        fullName: fullName,
        role: role,
      );
      final tokens = authResult.tokens;
      final now = DateTime.now();
      final user = User(
        id: authResult.identity.userID,
        phone: phoneNumber,
        fullName: fullName,
        role: role,
        avatar: null,
        isActive: true,
        createdAt: now,
        lastSeen: now,
      );
      if (role == UserRole.driver) {
        try {
          await _api.initializeDriverProfile(
            userID: user.id,
            accessToken: tokens.accessToken,
          );
        } catch (error) {
          debugPrint('Warning: Could not initialize driver profile: $error');
        }
      }
      await _saveSession(user, tokens);
      unawaited(_syncFcmTokenForSession(user, tokens.accessToken));
      state = state.copyWith(
        user: user,
        isLoading: false,
        clearError: true,
        clearPendingAuth: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _loginErrorMessage(error),
      );
    }
  }

  Future<void> resendSmsCode() async {
    final phoneNumber = state.phoneNumber;
    final fullName = state.pendingFullName;
    final role = state.pendingRole;

    if (phoneNumber == null || fullName == null || role == null) {
      state = state.copyWith(
        errorMessage:
            'Сессия подтверждения истекла. Запросите код заново.',
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      clearError: true,
      verificationId: 'backend-otp-pending',
      codeSentAt: DateTime.now(),
    );
    unawaited(_api.requestOtp(phone: phoneNumber, role: role));
  }

  Future<void> updateUserRole(UserRole role) async {
    final currentUser = state.user;
    if (currentUser == null) {
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final authResult = await _api.registerOrLogin(
        phone: currentUser.phone,
        fullName: currentUser.fullName,
        role: role,
        password: 'dev-password',
      );
      final tokens = authResult.tokens;
      final updated = currentUser.copyWith(
          id: authResult.identity.userID, role: role, lastSeen: DateTime.now());
      if (role == UserRole.driver) {
        try {
          await _api.initializeDriverProfile(
            userID: updated.id,
            accessToken: tokens.accessToken,
          );
        } catch (error) {
          debugPrint('Warning: Could not initialize driver profile: $error');
        }
      }
      await _saveSession(updated, tokens);
      unawaited(_syncFcmTokenForSession(updated, tokens.accessToken));
      state = state.copyWith(user: updated, isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось обновить роль.',
      );
    }
  }

  Future<String?>? _pendingRefresh;

  /// Refreshes the access token using the stored refresh token.
  /// Returns the new access token on success, or null on failure.
  /// Concurrent callers share a single in-flight refresh.
  Future<String?> refreshAccessToken() {
    return _pendingRefresh ??=
        _doRefresh().whenComplete(() => _pendingRefresh = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.read(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await signOut();
      return null;
    }
    try {
      final tokens = await _api.refresh(refreshToken: refreshToken);
      await _storage.write(_accessTokenKey, tokens.accessToken);
      await _storage.write(_refreshTokenKey, tokens.refreshToken);
      state = state.copyWith(accessToken: tokens.accessToken);
      return tokens.accessToken;
    } catch (_) {
      await signOut();
      return null;
    }
  }

  Future<void> signOut() async {
    // Clear all provider caches to prevent data leak between users
    try {
      _ref.invalidate(orderFlowProvider);
    } catch (_) {}
    try {
      _ref.invalidate(paymentWalletProvider);
    } catch (_) {}
    try {
      _ref.invalidate(clientPaymentMethodsProvider);
    } catch (_) {}
    try {
      _ref.invalidate(newDriverProvider);
    } catch (_) {}

    await _revokeCurrentFcmToken();
    await _storage.delete(_accessTokenKey);
    await _storage.delete(_refreshTokenKey);
    await _storage.delete(_userKey);
    state = state.copyWith(
      user: null,
      clearAccessToken: true,
      clearPendingAuth: true,
      clearError: true,
      isLoading: false,
    );
  }

  void resetAuth() {
    state = state.copyWith(
      isLoading: false,
      clearError: true,
      clearVerificationId: true,
      clearPendingAuth: true,
    );
  }

  void resetPhoneAuthFlow() {
    state = state.copyWith(
      isLoading: false,
      clearError: true,
      clearPendingAuth: true,
    );
  }

  Future<void> _restoreSession() async {
    try {
      final accessToken = await _storage.read(_accessTokenKey);
      final refreshToken = await _storage.read(_refreshTokenKey);
      final savedUser = await _readSavedUser();
      if (accessToken == null || refreshToken == null) {
        return;
      }

      String activeAccess = accessToken;
      try {
        final identity = await _api.me(accessToken: activeAccess);
        final restored = _composeUser(
          identity: identity,
          fallback: savedUser,
        );
        state = state.copyWith(
          user: restored,
          accessToken: activeAccess,
          isLoading: false,
        );
        unawaited(_syncFcmTokenForSession(restored, activeAccess));
        return;
      } catch (_) {
        // Try refresh once and retry me.
      }

      try {
        final tokens = await _api.refresh(refreshToken: refreshToken);
        activeAccess = tokens.accessToken;
        await _storage.write(_accessTokenKey, tokens.accessToken);
        await _storage.write(_refreshTokenKey, tokens.refreshToken);
        final identity = await _api.me(accessToken: activeAccess);
        final restored = _composeUser(
          identity: identity,
          fallback: savedUser,
        );
        await _storage.write(_userKey, jsonEncode(restored.toMap()));
        state = state.copyWith(
          user: restored,
          accessToken: activeAccess,
          isLoading: false,
        );
        unawaited(_syncFcmTokenForSession(restored, activeAccess));
      } catch (_) {
        await signOut();
      }
    } finally {
      // Notifier may be disposed before async restore finishes (tests,
      // hot-restart). Writing to `state` post-dispose throws — guard it.
      if (mounted) {
        state = state.copyWith(isRestoring: false);
      }
    }
  }

  Future<User?> _readSavedUser() async {
    final raw = await _storage.read(_userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return User.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(User user, AuthTokens tokens) async {
    await _storage.write(_accessTokenKey, tokens.accessToken);
    await _storage.write(_refreshTokenKey, tokens.refreshToken);
    await _storage.write(_userKey, jsonEncode(user.toMap()));
    state = state.copyWith(accessToken: tokens.accessToken);
  }

  void _bindFcmTokenRefresh() {
    try {
      _fcmTokenRefreshSubscription =
          PushNotificationService.instance.onTokenRefresh.listen((token) {
        final user = state.user;
        final accessToken = state.accessToken;
        if (user == null || accessToken == null || accessToken.isEmpty) {
          return;
        }
        unawaited(_registerFcmToken(
          user: user,
          accessToken: accessToken,
          fcmToken: token,
        ));
      });
    } catch (error) {
      debugPrint('FCM token refresh listener unavailable: $error');
    }
  }

  Future<void> _syncFcmTokenForSession(User user, String accessToken) async {
    try {
      final fcmToken = await PushNotificationService.instance.getToken();
      if (fcmToken == null || fcmToken.isEmpty) {
        return;
      }
      await _registerFcmToken(
        user: user,
        accessToken: accessToken,
        fcmToken: fcmToken,
      );
    } catch (error) {
      debugPrint('FCM token sync failed: $error');
    }
  }

  Future<void> _registerFcmToken({
    required User user,
    required String accessToken,
    required String fcmToken,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    await _api.registerFcmToken(
      accessToken: accessToken,
      fcmToken: fcmToken,
      role: user.role,
      platform: defaultTargetPlatform.name,
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
    );
  }

  Future<void> _revokeCurrentFcmToken() async {
    final user = state.user;
    final accessToken = state.accessToken;
    if (user == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final fcmToken = await PushNotificationService.instance.getToken();
      if (fcmToken == null || fcmToken.isEmpty) {
        return;
      }
      await _api.revokeFcmToken(
        accessToken: accessToken,
        fcmToken: fcmToken,
      );
    } catch (error) {
      debugPrint('FCM token revoke failed: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_fcmTokenRefreshSubscription?.cancel());
    super.dispose();
  }

  User _composeUser({
    required Identity identity,
    required User? fallback,
  }) {
    final now = DateTime.now();
    if (fallback == null) {
      return User(
        id: identity.userID,
        phone: '',
        fullName: 'Пользователь Авро',
        role: identity.role,
        avatar: null,
        isActive: true,
        createdAt: now,
        lastSeen: now,
      );
    }
    return fallback.copyWith(
      id: identity.userID,
      role: identity.role,
      lastSeen: now,
    );
  }

  String? _normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
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

  String? _deriveUserID(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 10) {
      return null;
    }
    return 'u$digits';
  }

  String _loginErrorMessage(Object error) {
    const fallback = 'Не удалось выполнить вход в систему.';
    if (error is! ApiClientException) {
      return fallback;
    }
    if (error.path == '/api/v1/auth/login') {
      return switch (error.statusCode) {
        401 => 'Неверные учётные данные.',
        429 => 'Слишком много запросов. Попробуйте позже.',
        _ => fallback,
      };
    }
    return fallback;
  }
}

class BackendAuthApi {
  const BackendAuthApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AuthResult> registerOrLogin({
    required String phone,
    required String fullName,
    required UserRole role,
    required String password,
  }) async {
    try {
      final json = await _apiClient.post('/api/v1/auth/register', {
        'phone': phone,
        'full_name': fullName,
        'role': role.name,
        'password': password,
      });
      return AuthResult.fromJson(json);
    } on ApiClientException catch (error) {
      if (error.statusCode != 409) rethrow;
      final json = await _apiClient.post('/api/v1/auth/login', {
        'phone': phone,
        'role': role.name,
        'password': password,
      });
      final tokens =
          AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>);
      final identity = await me(accessToken: tokens.accessToken);
      return AuthResult(tokens: tokens, identity: identity);
    }
  }

  Future<void> requestOtp({
    required String phone,
    required UserRole role,
  }) async {
    await _apiClient.post('/api/v1/auth/otp/request', {
      'phone': phone,
      'role': role.name,
    });
  }

  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    required String fullName,
    required UserRole role,
  }) async {
    final json = await _apiClient.post('/api/v1/auth/otp/verify', {
      'phone': phone,
      'code': code,
      'full_name': fullName,
      'role': role.name,
    });
    return AuthResult.fromJson(json);
  }

  Future<AuthTokens> refresh({required String refreshToken}) async {
    debugPrint('Calling refresh API');
    final json = await _apiClient.post('/api/v1/auth/refresh', {
      'refresh_token': refreshToken,
    });
    debugPrint('Refresh response: $json');
    return AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>);
  }

  Future<Identity> me({required String accessToken}) async {
    debugPrint('Calling me API');
    final json = await _apiClient.get(
      '/api/v1/auth/me',
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
      },
    );
    debugPrint('Me response: $json');
    final user = json['user'] as Map<String, dynamic>;
    return Identity.fromJson(user);
  }

  Future<void> initializeDriverProfile({
    required String userID,
    required String accessToken,
  }) async {
    debugPrint('Calling driver profile init API: $userID');
    final json = await _apiClient.post(
      '/api/v1/drivers/$userID/status',
      <String, dynamic>{
        'status': 'offline',
        'location': <String, dynamic>{
          'lat': 55.7558,
          'lng': 37.6176,
        },
      },
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
      },
    );
    debugPrint('Driver profile init response: $json');
  }

  Future<void> registerFcmToken({
    required String accessToken,
    required String fcmToken,
    required UserRole role,
    required String platform,
    required String appVersion,
  }) async {
    await _apiClient.post(
      '/api/v1/devices/fcm-token',
      <String, dynamic>{
        'fcm_token': fcmToken,
        'role': role.name,
        'platform': platform,
        'app_version': appVersion,
      },
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
      },
    );
  }

  Future<void> revokeFcmToken({
    required String accessToken,
    required String fcmToken,
  }) async {
    await _apiClient.post(
      '/api/v1/devices/fcm-token/revoke',
      <String, dynamic>{
        'fcm_token': fcmToken,
      },
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
      },
    );
  }
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token']?.toString() ?? '',
      refreshToken: json['refresh_token']?.toString() ?? '',
    );
  }
}

class AuthResult {
  const AuthResult({
    required this.tokens,
    required this.identity,
  });

  final AuthTokens tokens;
  final Identity identity;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      tokens: AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>),
      identity: Identity.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class Identity {
  const Identity({
    required this.userID,
    required this.role,
  });

  final String userID;
  final UserRole role;

  factory Identity.fromJson(Map<String, dynamic> json) {
    return Identity(
      userID: json['id']?.toString() ?? '',
      role: _parseRole(json['role']?.toString()),
    );
  }

  static UserRole _parseRole(String? raw) {
    switch (raw) {
      case 'driver':
        return UserRole.driver;
      case 'admin':
        return UserRole.admin;
      case 'client':
      default:
        return UserRole.client;
    }
  }
}
