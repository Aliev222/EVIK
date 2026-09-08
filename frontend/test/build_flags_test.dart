import 'package:flutter_test/flutter_test.dart';
import 'package:tow_truck_frontend/core/config/build_flags.dart';

void main() {
  test('development feature flags are always disabled in release mode', () {
    expect(
      developmentFeatureEnabled(requested: true, releaseMode: true),
      isFalse,
    );
  });

  test('development feature flags follow dart-define outside release mode', () {
    expect(
      developmentFeatureEnabled(requested: true, releaseMode: false),
      isTrue,
    );
    expect(
      developmentFeatureEnabled(requested: false, releaseMode: false),
      isFalse,
    );
  });
}
