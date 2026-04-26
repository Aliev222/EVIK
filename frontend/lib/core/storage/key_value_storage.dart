abstract class KeyValueStorage {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class InMemoryKeyValueStorage implements KeyValueStorage {
  final Map<String, String> _storage = <String, String>{};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async {
    // TODO: Replace with persistent storage (SharedPreferences/SecureStorage).
    _storage[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }
}
