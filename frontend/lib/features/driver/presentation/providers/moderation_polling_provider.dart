import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import 'driver_verification_provider.dart';
import 'driver_tax_profile_provider.dart';

class ModerationPollingState {
  const ModerationPollingState({
    required this.isPolling,
    required this.lastUpdate,
    this.error,
  });

  final bool isPolling;
  final DateTime lastUpdate;
  final String? error;

  ModerationPollingState copyWith({
    bool? isPolling,
    DateTime? lastUpdate,
    String? error,
  }) {
    return ModerationPollingState(
      isPolling: isPolling ?? this.isPolling,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error,
    );
  }
}

class ModerationPollingNotifier extends StateNotifier<ModerationPollingState> {
  ModerationPollingNotifier(this._ref)
      : super(ModerationPollingState(
          isPolling: false,
          lastUpdate: DateTime.now(),
        ));

  final Ref _ref;
  Timer? _timer;
  static const Duration _pollingInterval = Duration(seconds: 30);

  void startPolling() {
    if (state.isPolling) return;

    state = state.copyWith(isPolling: true, error: null);

    // Initial check
    _checkStatuses();

    // Set up periodic polling
    _timer = Timer.periodic(_pollingInterval, (_) {
      _checkStatuses();
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(isPolling: false);
  }

  Future<void> _checkStatuses() async {
    try {
      final userId = _ref.read(authProvider).user?.id;
      if (userId == null) return;

      // Refresh verification status
      _ref.invalidate(autoRefreshingVerificationStatusProvider(userId));

      // Refresh tax profile status
      _ref.invalidate(driverTaxProfileProvider(userId));

      state = state.copyWith(
        lastUpdate: DateTime.now(),
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        lastUpdate: DateTime.now(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final moderationPollingProvider =
    StateNotifierProvider<ModerationPollingNotifier, ModerationPollingState>(
  (ref) => ModerationPollingNotifier(ref),
);

// Provider to automatically start/stop polling based on verification status
final autoModerationPollingProvider = Provider((ref) {
  final userId = ref.watch(authProvider).user?.id;

  if (userId == null) return;

  final verificationStatus = ref.watch(autoRefreshingVerificationStatusProvider(userId));
  final taxProfile = ref.watch(driverTaxProfileProvider(userId));

  final pollingNotifier = ref.watch(moderationPollingProvider.notifier);

  // Start polling if documents are submitted and pending verification
  verificationStatus.whenData((status) {
    final shouldPoll = status.status == 'pending' ||
                      (taxProfile.valueOrNull?.verificationStatus == 'pending');

    if (shouldPoll) {
      pollingNotifier.startPolling();
    } else {
      pollingNotifier.stopPolling();
    }
  });

  return null;
});