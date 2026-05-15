abstract class ApiClient {
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? headers});

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  });

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  });

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  });
}

const defaultApiBaseUrl = String.fromEnvironment(
  'EVIK_API_BASE_URL',
  defaultValue: 'https://evik-backend.onrender.com',
);

class ApiClientException implements Exception {
  const ApiClientException({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.message,
    required this.uri,
  });

  final String method;
  final String path;
  final int statusCode;
  final String message;
  final Uri uri;

  @override
  String toString() => '$method $path failed with $statusCode: $message';
}
