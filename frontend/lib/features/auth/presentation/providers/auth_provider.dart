import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/bootstrap/app_bootstrap.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import '../../../../core/storage/key_value_storage.dart';
import '../../domain/entities/user.dart';

const _accessTokenKey = 'auth_access_token';
const _refreshTokenKey = 'auth_refresh_token';
const _userKey = 'auth_user';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    api: BackendAuthApi(
      apiClient: platform_api.createPlatformApiClient(),
    ),
    storage: ref.read(keyValueStorageProvider),
  );
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider.select((state) => state.user));
});

class AuthState {
  const AuthState({
    this.user,
    this.accessToken,
    this.isLoading = false,
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
  })  : _api = api,
        _storage = storage,
        super(const AuthState()) {
    unawaited(_restoreSession());
  }

  final BackendAuthApi _api;
  final KeyValueStorage _storage;

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
            'Р’РІРµРґРёС‚Рµ РєРѕСЂСЂРµРєС‚РЅС‹Р№ РЅРѕРјРµСЂ С‚РµР»РµС„РѕРЅР°.',
      );
      return;
    }

    final trimmedName = fullName.trim();
    if (trimmedName.length < 2) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Р’РІРµРґРёС‚Рµ РёРјСЏ РЅРµ РєРѕСЂРѕС‡Рµ 2 СЃРёРјРІРѕР»РѕРІ.',
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

    // OTP delivery is migrated later. For now we keep the same UX step and
    // verify code client-side before requesting backend login.
    state = state.copyWith(isLoading: false);
  }

  Future<void> verifySmsCode(String code) async {
    final sanitizedCode = code.replaceAll(RegExp(r'[^\d]'), '');
    if (sanitizedCode.length != 6) {
      state =
          state.copyWith(errorMessage: 'Р’РІРµРґРёС‚Рµ 6 С†РёС„СЂ РёР· SMS.');
      return;
    }

    final phoneNumber = state.phoneNumber;
    final fullName = state.pendingFullName;
    final role = state.pendingRole;
    if (phoneNumber == null || fullName == null || role == null) {
      state = state.copyWith(
        errorMessage:
            'РЎРµСЃСЃРёСЏ РїРѕРґС‚РІРµСЂР¶РґРµРЅРёСЏ РёСЃС‚РµРєР»Р°. Р—Р°РїСЂРѕСЃРёС‚Рµ РєРѕРґ Р·Р°РЅРѕРІРѕ.',
      );
      return;
    }

    final userID = _deriveUserID(phoneNumber);
    if (userID == null) {
      state = state.copyWith(
        errorMessage:
            'РќРµ СѓРґР°Р»РѕСЃСЊ СЃС„РѕСЂРјРёСЂРѕРІР°С‚СЊ РёРґРµРЅС‚РёС„РёРєР°С‚РѕСЂ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tokens = await _api.login(userID: userID, role: role);
      final now = DateTime.now();
      final user = User(
        id: userID,
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
            userID: userID,
            accessToken: tokens.accessToken,
          );
        } catch (error) {
          debugPrint('Warning: Could not initialize driver profile: $error');
        }
      }
      await _saveSession(user, tokens);
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
            'РЎРµСЃСЃРёСЏ РїРѕРґС‚РІРµСЂР¶РґРµРЅРёСЏ РёСЃС‚РµРєР»Р°. Р—Р°РїСЂРѕСЃРёС‚Рµ РєРѕРґ Р·Р°РЅРѕРІРѕ.',
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      clearError: true,
      verificationId: 'backend-otp-pending',
      codeSentAt: DateTime.now(),
    );
  }

  Future<void> updateUserRole(UserRole role) async {
    final currentUser = state.user;
    if (currentUser == null) {
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tokens = await _api.login(userID: currentUser.id, role: role);
      final updated =
          currentUser.copyWith(role: role, lastSeen: DateTime.now());
      if (role == UserRole.driver) {
        try {
          await _api.initializeDriverProfile(
            userID: currentUser.id,
            accessToken: tokens.accessToken,
          );
        } catch (error) {
          debugPrint('Warning: Could not initialize driver profile: $error');
        }
      }
      await _saveSession(updated, tokens);
      state = state.copyWith(user: updated, isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'РќРµ СѓРґР°Р»РѕСЃСЊ РѕР±РЅРѕРІРёС‚СЊ СЂРѕР»СЊ.',
      );
    }
  }

  Future<void> signOut() async {
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
    } catch (_) {
      await signOut();
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

  User _composeUser({
    required Identity identity,
    required User? fallback,
  }) {
    final now = DateTime.now();
    if (fallback == null) {
      return User(
        id: identity.userID,
        phone: '',
        fullName: 'EVIK User',
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
    const fallback = 'Не удалось выполнить вход через сервер.';
    if (error is! ApiClientException) {
      return fallback;
    }
    if (error.path == '/api/v1/auth/login') {
      return switch (error.statusCode) {
        401 => 'Неверные учетные данные.',
        429 => 'Слишком много попыток. Попробуйте позже.',
        _ => fallback,
      };
    }
    return fallback;
  }
}

class BackendAuthApi {
  const BackendAuthApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AuthTokens> login({
    required String userID,
    required UserRole role,
  }) async {
    debugPrint('Calling login API: $userID, $role');
    final json = await _apiClient.post('/api/v1/auth/login', {
      'user_id': userID,
      'role': role.name,
    });
    debugPrint('Login response: $json');
    return AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>);
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
