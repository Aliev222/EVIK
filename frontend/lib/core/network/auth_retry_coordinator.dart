import 'dart:async';

typedef AuthorizationRefreshCallback = Future<String?> Function();
typedef SessionLogoutCallback = Future<void> Function();

class AuthRetryCoordinator {
  AuthRetryCoordinator._();

  static AuthorizationRefreshCallback? _refresh;
  static SessionLogoutCallback? _logout;
  static String? Function()? _accessToken;

  static void configure({
    required AuthorizationRefreshCallback refresh,
    required SessionLogoutCallback logout,
    String? Function()? accessToken,
  }) {
    _refresh = refresh;
    _logout = logout;
    _accessToken = accessToken;
  }

  static Future<String?> refreshAccessToken() async => _refresh?.call();

  static Future<void> logout() async {
    await _logout?.call();
  }

  /// Returns the current access token (if registered) for clients that live
  /// outside the Riverpod tree and still need authenticated backend calls.
  static String? accessToken() => _accessToken?.call();
}
