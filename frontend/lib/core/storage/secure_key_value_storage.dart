import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_storage.dart';

class SecureKeyValueStorage implements KeyValueStorage {
  SecureKeyValueStorage({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const AndroidOptions _androidOptions = AndroidOptions();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(
        key: key,
        value: value,
        aOptions: _androidOptions,
      );
    } catch (error, stackTrace) {
      debugPrint('Secure storage write failed for key "$key": $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'secure_key_value_storage',
          context: ErrorDescription('while writing a secure storage value'),
        ),
      );
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      return _storage.read(
        key: key,
        aOptions: _androidOptions,
      );
    } catch (error, stackTrace) {
      debugPrint('Secure storage read failed for key "$key": $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'secure_key_value_storage',
          context: ErrorDescription('while reading a secure storage value'),
        ),
      );
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(
        key: key,
        aOptions: _androidOptions,
      );
    } catch (error, stackTrace) {
      debugPrint('Secure storage delete failed for key "$key": $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'secure_key_value_storage',
          context: ErrorDescription('while deleting a secure storage value'),
        ),
      );
    }
  }
}
