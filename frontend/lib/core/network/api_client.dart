import 'package:flutter/foundation.dart';

abstract class ApiClient {
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? headers});
  Future<Map<String, dynamic>> post(
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
  defaultValue: kDebugMode
      ? 'http://localhost:8080' // Development
      : 'https://evik-backend.onrender.com', // Production на Render
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

  static bool _driverOnline = false;

  static final List<Map<String, dynamic>> _paymentCards =
      <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'local-card-4242',
      'brand': 'visa',
      'last4': '4242',
      'exp_month': 12,
      'exp_year': 2027,
      'holder': 'EVIK CLIENT',
      'is_default': true,
      'created_at': '2026-04-01T00:00:00Z',
    },
  ];
  static Map<String, dynamic>? _promocode;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (path == '/api/v1/auth/me') {
      return <String, dynamic>{
        'user': <String, dynamic>{'id': 'local-user', 'role': 'client'},
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
    if (path == '/api/v1/drivers/local-driver') {
      return <String, dynamic>{
        'driver': <String, dynamic>{
          'id': 'local-driver',
          'user_id': 'local-driver',
          'status': _driverOnline ? 'online' : 'offline',
          'current_order_id': null,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
      };
    }
    if (path.startsWith('/api/v1/orders?status=')) {
      final status = Uri.parse(path).queryParameters['status'] ?? 'searching';
      return <String, dynamic>{
        'orders': status == 'searching'
            ? <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'local-order-101',
                  'user_id': 'local-client',
                  'driver_id': null,
                  'pickup_lat': 55.7601,
                  'pickup_lng': 37.6188,
                  'dropoff_lat': 55.7468,
                  'dropoff_lng': 37.6352,
                  'tow_truck_type': 'winch',
                  'notes': 'Заблокировано колес: 2',
                  'status': 'searching',
                  'created_at': DateTime.now()
                      .subtract(const Duration(minutes: 8))
                      .toUtc()
                      .toIso8601String(),
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                },
                <String, dynamic>{
                  'id': 'local-order-102',
                  'user_id': 'local-client',
                  'driver_id': null,
                  'pickup_lat': 55.7524,
                  'pickup_lng': 37.6041,
                  'dropoff_lat': 55.7711,
                  'dropoff_lng': 37.6508,
                  'tow_truck_type': 'platform',
                  'notes': 'Заблокировано колес: 4',
                  'status': 'searching',
                  'created_at': DateTime.now()
                      .subtract(const Duration(minutes: 14))
                      .toUtc()
                      .toIso8601String(),
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                },
              ]
            : <Map<String, dynamic>>[],
      };
    }
    if (path == '/api/v1/payments/wallet') {
      return <String, dynamic>{
        'cards': _paymentCards,
        'payments': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'local-payment-1',
            'order_id': 'local-order-1',
            'title': 'Эвакуация · Тверская',
            'amount': -2300,
            'status': 'completed',
            'created_at': '2026-04-23T12:00:00Z',
          },
          <String, dynamic>{
            'id': 'local-payment-2',
            'order_id': 'local-order-2',
            'title': 'Эвакуация · Садовое',
            'amount': -1800,
            'status': 'completed',
            'created_at': '2026-04-19T12:00:00Z',
          },
        ],
        if (_promocode != null) 'promocode': _promocode,
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
        },
      };
    }
    if (path == '/api/v1/drivers/local-driver/status') {
      _driverOnline = body['status']?.toString() == 'online';
      return <String, dynamic>{
        'driver': <String, dynamic>{
          'id': 'local-driver',
          'user_id': 'local-driver',
          'status': _driverOnline ? 'online' : 'offline',
          'current_order_id': null,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
      };
    }
    if (path.startsWith('/api/v1/orders/') && path.endsWith('/accept')) {
      final id = path.split('/')[4];
      return <String, dynamic>{
        'order': <String, dynamic>{
          'id': id,
          'user_id': 'local-client',
          'driver_id': 'local-driver',
          'pickup_lat': 55.7601,
          'pickup_lng': 37.6188,
          'dropoff_lat': 55.7468,
          'dropoff_lng': 37.6352,
          'tow_truck_type': 'winch',
          'notes': 'Заблокировано колес: 2',
          'status': 'accepted',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
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
        },
      };
    }
    if (path == '/api/v1/payments/cards') {
      final digits =
          body['card_number']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      final last4 =
          digits.length >= 4 ? digits.substring(digits.length - 4) : '0000';
      for (final card in _paymentCards) {
        card['is_default'] = false;
      }
      final card = <String, dynamic>{
        'id': 'local-card-$last4',
        'brand': digits.startsWith('4') ? 'visa' : 'mastercard',
        'last4': last4,
        'exp_month': body['exp_month'] ?? 12,
        'exp_year': body['exp_year'] ?? 2028,
        'holder': body['holder']?.toString() ?? 'EVIK CLIENT',
        'is_default': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      _paymentCards.insert(0, card);
      return <String, dynamic>{'card': card};
    }
    if (path.startsWith('/api/v1/payments/cards/') &&
        path.endsWith('/default')) {
      final parts = path.split('/');
      final cardId = parts.length > 5 ? parts[5] : '';
      Map<String, dynamic>? selected;
      for (final card in _paymentCards) {
        final isSelected = card['id'] == cardId;
        card['is_default'] = isSelected;
        if (isSelected) selected = card;
      }
      return <String, dynamic>{'card': selected ?? _paymentCards.first};
    }
    if (path == '/api/v1/payments/promocode/apply') {
      final code = body['code']?.toString().trim().toUpperCase() ?? '';
      if (code != 'EVIK2025') {
        throw ApiClientException(
          method: 'POST',
          path: path,
          statusCode: 400,
          message: 'invalid promocode',
          uri: Uri(path: path),
        );
      }
      _promocode = <String, dynamic>{
        'code': code,
        'description': 'Скидка 10% на следующую поездку',
        'discount_pct': 10,
      };
      return <String, dynamic>{'promocode': _promocode};
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (path.startsWith('/api/v1/payments/cards/')) {
      final parts = path.split('/');
      final cardId = parts.length > 5 ? parts[5] : '';
      final removedIndex = _paymentCards.indexWhere(
        (card) => card['id'] == cardId,
      );
      if (removedIndex >= 0) {
        final wasDefault = _paymentCards[removedIndex]['is_default'] == true;
        _paymentCards.removeAt(removedIndex);
        if (wasDefault && _paymentCards.isNotEmpty) {
          _paymentCards.first['is_default'] = true;
        }
      }
      return <String, dynamic>{'deleted': true};
    }
    return <String, dynamic>{};
  }
}
