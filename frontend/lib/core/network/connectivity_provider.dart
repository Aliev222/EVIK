import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `false` while the device reports no connectivity at all.
/// Lightweight, app-wide "no internet" signal used by banner UIs.
final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  final controller = StreamController<bool>.broadcast();

  bool hasNetwork(List<ConnectivityResult> results) {
    return !results.contains(ConnectivityResult.none);
  }

  Future<void> emit() async {
    final results = await connectivity.checkConnectivity();
    if (!controller.isClosed) {
      controller.add(hasNetwork(results));
    }
  }

  unawaited(emit());

  final subscription = connectivity.onConnectivityChanged.listen(
    (results) {
      if (!controller.isClosed) {
        controller.add(hasNetwork(results));
      }
    },
  );

  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });

  return controller.stream;
});