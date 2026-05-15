import 'dart:async';

typedef AuthorizationRefreshCallback = Future<String?> Function();
typedef SessionLogoutCallback = Future<void> Function();

class AuthRetryCoordinator {
  AuthRetryCoordinator._();

  static AuthorizationRefreshCallback? _refresh;
  static SessionLogoutCallback? _logout;

  static void configure({
    required AuthorizationRefreshCallback refresh,
    required SessionLogoutCallback logout,
  }) {
    _refresh = refresh;
    _logout = logout;
  }

  static Future<String?> refreshAccessToken() async => _refresh?.call();

  static Future<void> logout() async {
    await _logout?.call();
  }
}
