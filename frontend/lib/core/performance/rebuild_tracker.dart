import 'package:flutter/foundation.dart';

class RebuildTracker {
  static bool _isInitialized = false;
  static final Map<String, int> _rebuildCounts = {};
  static final Map<String, DateTime> _lastRebuild = {};
  static int _totalRebuilds = 0;

  static void initialize() {
    if (_isInitialized || !kDebugMode) return;
    _isInitialized = true;

    debugPrint('🔍 Rebuild tracker initialized');

    // Print summary every 5 seconds
    _startPeriodicLogging();
  }

  static void trackRebuild(String widgetName) {
    if (!kDebugMode) return;

    _rebuildCounts[widgetName] = (_rebuildCounts[widgetName] ?? 0) + 1;
    _lastRebuild[widgetName] = DateTime.now();
    _totalRebuilds++;

    // Log excessive rebuilds
    final count = _rebuildCounts[widgetName]!;
    if (count > 10 && count % 5 == 0) {
      debugPrint('🔄 Frequent rebuilds: $widgetName ($count times)');
    }
  }

  static void _startPeriodicLogging() {
    if (!kDebugMode) return;

    Future.delayed(const Duration(seconds: 10), () {
      _logSummary();
      _startPeriodicLogging();
    });
  }

  static void _logSummary() {
    if (_totalRebuilds == 0) return;

    debugPrint('📊 Rebuild Summary ($_totalRebuilds total):');

    // Sort by rebuild count
    final sorted = _rebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Show top 5 most rebuilt widgets
    for (int i = 0; i < sorted.length && i < 5; i++) {
      final entry = sorted[i];
      final lastTime = _lastRebuild[entry.key];
      final ago =
          lastTime != null ? DateTime.now().difference(lastTime).inSeconds : 0;

      debugPrint('   ${entry.key}: ${entry.value} (${ago}s ago)');
    }

    // Warn about excessive rebuilds
    final excessive = sorted.where((e) => e.value > 20).length;
    if (excessive > 0) {
      debugPrint('⚠️  $excessive widgets with >20 rebuilds');
    }
  }

  static void reset() {
    _rebuildCounts.clear();
    _lastRebuild.clear();
    _totalRebuilds = 0;
    debugPrint('🔄 Rebuild tracking reset');
  }

  static Map<String, dynamic> getStats() {
    return {
      'totalRebuilds': _totalRebuilds,
      'uniqueWidgets': _rebuildCounts.length,
      'topRebuilders': _rebuildCounts.entries
          .map((e) => {'widget': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int))
    };
  }
}
