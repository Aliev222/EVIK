import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class FrameTimingMonitor {
  static bool _isInitialized = false;
  static final List<FrameTiming> _frameTimings = [];
  static int _frameCount = 0;
  static double _totalBuildTime = 0;
  static double _totalRasterTime = 0;
  static int _droppedFrames = 0;

  static void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    if (kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
      debugPrint('🔍 Frame timing monitor initialized');
    }
  }

  static void _onFrameTiming(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameTimings.add(timing);
      _frameCount++;

      final buildTime = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterTime = timing.rasterDuration.inMicroseconds / 1000.0;
      final totalTime = timing.totalSpan.inMicroseconds / 1000.0;

      _totalBuildTime += buildTime;
      _totalRasterTime += rasterTime;

      // Frame is dropped if total time > 16.67ms (60fps threshold)
      if (totalTime > 16.67) {
        _droppedFrames++;
      }

      // Log expensive frames
      if (totalTime > 25.0) {
        debugPrint('🐌 Expensive frame: ${totalTime.toStringAsFixed(1)}ms '
            '(build: ${buildTime.toStringAsFixed(1)}ms, '
            'raster: ${rasterTime.toStringAsFixed(1)}ms)');
      }

      // Periodic summary (every 60 frames)
      if (_frameCount % 60 == 0) {
        _logSummary();
      }
    }

    // Keep only last 240 frames (4 seconds at 60fps)
    if (_frameTimings.length > 240) {
      _frameTimings.removeAt(0);
    }
  }

  static void _logSummary() {
    if (_frameCount == 0) return;

    final avgBuild = _totalBuildTime / _frameCount;
    final avgRaster = _totalRasterTime / _frameCount;
    final dropRate = (_droppedFrames / _frameCount) * 100;

    debugPrint('📊 Frame Stats ($_frameCount frames):');
    debugPrint('   Avg build: ${avgBuild.toStringAsFixed(1)}ms');
    debugPrint('   Avg raster: ${avgRaster.toStringAsFixed(1)}ms');
    debugPrint(
        '   Dropped frames: $_droppedFrames (${dropRate.toStringAsFixed(1)}%)');

    if (dropRate > 10) {
      debugPrint('⚠️  High frame drop rate detected!');
    }
  }

  static void logCurrentStats() {
    _logSummary();
  }

  static void reset() {
    _frameTimings.clear();
    _frameCount = 0;
    _totalBuildTime = 0;
    _totalRasterTime = 0;
    _droppedFrames = 0;
    debugPrint('🔄 Frame timing stats reset');
  }

  static Map<String, dynamic> getStats() {
    if (_frameCount == 0) {
      return {
        'frameCount': 0,
        'avgBuildTime': 0.0,
        'avgRasterTime': 0.0,
        'droppedFrames': 0,
        'dropRate': 0.0,
      };
    }

    return {
      'frameCount': _frameCount,
      'avgBuildTime': _totalBuildTime / _frameCount,
      'avgRasterTime': _totalRasterTime / _frameCount,
      'droppedFrames': _droppedFrames,
      'dropRate': (_droppedFrames / _frameCount) * 100,
    };
  }
}
