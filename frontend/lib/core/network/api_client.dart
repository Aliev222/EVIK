import 'package:flutter/foundation.dart';

abstract class ApiClient {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  });
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  });
}

const defaultApiBaseUrl = String.fromEnvironment(
  'EVIK_API_BASE_URL',
  defaultValue: kDebugMode
    ? 'http://localhost:8080'  // Development
    : 'https://evik-backend.onrender.com',   // Production на Render
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

class NoOpApiClient implements ApiClient {
  const NoOpApiClient();

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (path == '/api/v1/auth/me') {
      return <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'local-user',
          'role': 'client',
        }
      };
    }
    if (path.startsWith('/api/v1/orders/local-')) {
      final id = path.split('/').last;
      return <String, dynamic>{
        'order': <String, dynamic>{
          'id': id,
          'user_id': 'local-user',
          'pickup_lat': 0.0,
          'pickup_lng': 0.0,
          'dropoff_lat': 0.0,
          'dropoff_lng': 0.0,
          'status': 'searching',
          'driver_id': null,
        },
      };
    }
    return <String, dynamic>{'orders': <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    if (path == '/api/v1/auth/login' || path == '/api/v1/auth/refresh') {
      return <String, dynamic>{
        'tokens': <String, dynamic>{
          'access_token': 'local-access-token',
          'refresh_token': 'local-refresh-token',
          'token_type': 'Bearer',
        },
        'user': <String, dynamic>{
          'id': body['user_id']?.toString() ?? 'local-user',
          'role': body['role']?.toString() ?? 'client',
        },
      };
    }
    if (path.startsWith('/api/v1/orders/') && path.endsWith('/cancel')) {
      final id = path.split('/')[3];
      return {
        'order': {
          'id': id,
          'user_id': 'local-user',
          'pickup_lat': 0.0,
          'pickup_lng': 0.0,
          'dropoff_lat': 0.0,
          'dropoff_lng': 0.0,
          'status': 'cancelled',
          'driver_id': null,
        }
      };
    }
    // TODO: Replace with real HTTP client implementation.
    if (path == '/api/v1/orders') {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      return {
        'order': {
          'id': 'local-$now',
          'user_id': body['user_id'] ?? 'local-user',
          'pickup_lat': (body['pickup_lat'] as num?)?.toDouble() ?? 0.0,
          'pickup_lng': (body['pickup_lng'] as num?)?.toDouble() ?? 0.0,
          'dropoff_lat': (body['dropoff_lat'] as num?)?.toDouble() ?? 0.0,
          'dropoff_lng': (body['dropoff_lng'] as num?)?.toDouble() ?? 0.0,
          'status': 'searching',
          'driver_id': null,
        }
      };
    }
    return <String, dynamic>{};
  }
}
