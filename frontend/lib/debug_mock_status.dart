import 'package:flutter/foundation.dart';
import 'core/constants/app_constants.dart';

void printMockStatus() {
  debugPrint('=== AVRO DEBUG INFO ===');
  debugPrint('Mock Mode: ${AppConstants.useMockData}');
  debugPrint('Environment Variables:');
  debugPrint('  USE_MOCK_DATA: ${const String.fromEnvironment('USE_MOCK_DATA')}');
  debugPrint('======================');
}