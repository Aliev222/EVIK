import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';

const _driverWasOnlineKey = 'driver_was_online';

/// Persists an active driver shift and restores it after an FCM wake-up.
class DriverWakeService {
  DriverWakeService(this._ref);

  final Ref _ref;
  Future<void>? _ensureOnlineOperation;

  Future<void> markOnline() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_driverWasOnlineKey, true);
    } catch (_) {
      // The server remains the source of truth if local persistence is absent.
    }
  }

  Future<void> markOffline() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_driverWasOnlineKey, false);
    } catch (_) {
      // The server remains the source of truth if local persistence is absent.
    }
  }

  Future<bool> wasOnline() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_driverWasOnlineKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Coalesces startup and push wake-ups so an online transition runs once.
  Future<void> ensureOnline() {
    final activeOperation = _ensureOnlineOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    late final Future<void> operation;
    operation = _ensureOnline().whenComplete(() {
      if (identical(_ensureOnlineOperation, operation)) {
        _ensureOnlineOperation = null;
      }
    });
    _ensureOnlineOperation = operation;
    return operation;
  }

  Future<void> _ensureOnline() async {
    final auth = _ref.read(authProvider);
    if (auth.isRestoring || auth.user?.role != UserRole.driver || auth.accessToken == null) return;
    await _ref.read(newDriverProvider.notifier).resumeOnlineSession();
  }
}

final driverWakeServiceProvider = Provider<DriverWakeService>((ref) {
  return DriverWakeService(ref);
});
