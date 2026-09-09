import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tow_truck_frontend/features/driver/data/services/driver_shift_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new day reset does not resurrect a stale active shift', () async {
    final staleStart = DateTime(2026, 1, 1, 9).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'driver_shift.date': '2026-01-01',
      'driver_shift.accumulated_seconds': 5 * 60 * 60,
      'driver_shift.shift_started_at': staleStart,
      'driver_shift.long_alerted': true,
    });

    final firstRestore = DriverShiftTracker();
    await firstRestore.restore();
    expect(firstRestore.isOnShift, isFalse);
    expect(firstRestore.totalShiftSeconds, 0);

    final secondRestore = DriverShiftTracker();
    await secondRestore.restore();
    expect(secondRestore.isOnShift, isFalse);
    expect(secondRestore.totalShiftSeconds, 0);
  });
}
