import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/core/storage/secure_key_value_storage.dart';

final keyValueStorageProvider = Provider<KeyValueStorage>((ref) {
  return SecureKeyValueStorage();
});

List<Override> buildAppOverrides() {
  return [
    keyValueStorageProvider.overrideWith((ref) {
      return SecureKeyValueStorage();
    }),
  ];
}
