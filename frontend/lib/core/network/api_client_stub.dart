import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import '../constants/app_constants.dart';

ApiClient createPlatformApiClient({String baseUrl = defaultApiBaseUrl}) {
  // Используем Mock если включен флаг
  if (AppConstants.useMockData) {
    return MockApiClient();
  }
  return HttpApiClient(baseUrl: baseUrl);
}

// Мок API клиент с заглушками
class MockApiClient implements ApiClient {
  static const String _mockUserId = 'mock_user_123';
  static const String _mockDriverId = 'mock_driver_456';
  static const String _mockOrderId = 'mock_order_789';

  final Random _random = Random();

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(800)));

    return _handleMockRequest('GET', path, {});
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    await Future.delayed(Duration(milliseconds: 300 + _random.nextInt(700)));

    return _handleMockRequest('POST', path, body);
  }

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(500)));

    return _handleMockRequest('DELETE', path, {});
  }

  Map<String, dynamic> _handleMockRequest(
    String method,
    String path,
    Map<String, dynamic> body,
  ) {
    dev.log('[MOCK API] $method $path');

    // Auth endpoints
    if (path.contains('/auth/')) {
      return _handleAuthEndpoints(path, body);
    }

    // User endpoints
    if (path.contains('/users/')) {
      return _handleUserEndpoints(path, body);
    }

    // Driver endpoints
    if (path.contains('/drivers/')) {
      return _handleDriverEndpoints(path, body);
    }

    // Order endpoints
    if (path.contains('/orders/')) {
      return _handleOrderEndpoints(path, body);
    }

    // Payment endpoints
    if (path.contains('/payments/')) {
      return _handlePaymentEndpoints(path, body);
    }

    // Default success response
    return {'success': true, 'message': 'Mock response'};
  }

  Map<String, dynamic> _handleAuthEndpoints(
      String path, Map<String, dynamic> body) {
    if (path.endsWith('/send-sms')) {
      return {
        'success': true,
        'message': 'SMS код отправлен (Mock)',
        'sessionId': 'mock_session_${_random.nextInt(9999)}'
      };
    }

    if (path.endsWith('/verify-sms')) {
      return {
        'success': true,
        'user': _generateMockUser(),
        'accessToken': 'mock_access_token_${_random.nextInt(9999)}',
        'refreshToken': 'mock_refresh_token_${_random.nextInt(9999)}',
      };
    }

    if (path.contains('/auth/login')) {
      final role = body['role'] as String? ?? 'client';
      return {
        'success': true,
        'tokens': {
          'access_token': 'mock_access_${_random.nextInt(9999)}',
          'refresh_token': 'mock_refresh_${_random.nextInt(9999)}',
        },
        'user': _generateMockUser(role: role),
      };
    }

    if (path.contains('/auth/refresh')) {
      return {
        'success': true,
        'tokens': {
          'access_token': 'mock_access_refreshed_${_random.nextInt(9999)}',
          'refresh_token': 'mock_refresh_refreshed_${_random.nextInt(9999)}',
        }
      };
    }

    if (path.contains('/auth/me')) {
      return {
        'success': true,
        'user': {
          'id': _mockUserId,
          'role': 'client',
          'name': 'Тестовый Пользователь',
        }
      };
    }

    return {'success': true};
  }

  Map<String, dynamic> _handleUserEndpoints(
      String path, Map<String, dynamic> body) {
    if (path.endsWith('/profile')) {
      return {
        'success': true,
        'user': _generateMockUser(),
      };
    }

    return {'success': true};
  }

  Map<String, dynamic> _handleDriverEndpoints(
      String path, Map<String, dynamic> body) {
    if (path.endsWith('/profile')) {
      return {
        'success': true,
        'driver': _generateMockDriver(),
      };
    }

    if (path.endsWith('/status')) {
      final isOnline = _random.nextBool();
      return {
        'success': true,
        'driver': {
          ..._generateMockDriver(),
          'isOnline': isOnline,
          'status': isOnline ? 'online' : 'offline',
        }
      };
    }

    if (path.contains('/orders/available')) {
      return {
        'success': true,
        'orders': _generateMockAvailableOrders(),
      };
    }

    if (path.contains('/orders/active')) {
      final hasActiveOrder = _random.nextBool();
      return {
        'success': true,
        'order': hasActiveOrder ? _generateMockActiveOrder() : null,
      };
    }

    if (path.endsWith('/earnings')) {
      return {
        'success': true,
        'earnings': _generateMockEarnings(),
      };
    }

    // Driver profile initialization
    if (path.contains('/drivers/') && path.endsWith('/status')) {
      return {
        'success': true,
        'message': 'Driver profile initialized (Mock)',
      };
    }

    return {'success': true};
  }

  Map<String, dynamic> _handleOrderEndpoints(
      String path, Map<String, dynamic> body) {
    if (path.endsWith('/create')) {
      return {
        'success': true,
        'order': _generateMockOrder(status: 'searching'),
      };
    }

    if (path.endsWith('/history')) {
      return {
        'success': true,
        'orders': _generateMockOrderHistory(),
      };
    }

    if (path.contains('/accept')) {
      return {
        'success': true,
        'order': _generateMockOrder(status: 'assigned'),
      };
    }

    return {'success': true};
  }

  Map<String, dynamic> _handlePaymentEndpoints(
    String path,
    Map<String, dynamic> body,
  ) {
    if (path.endsWith('/wallet')) {
      return {
        'cards': [
          {
            'id': 'mock_card_4242',
            'brand': 'visa',
            'last4': '4242',
            'exp_month': 12,
            'exp_year': 2027,
            'holder': 'EVIK CLIENT',
            'is_default': true,
            'created_at': DateTime.now()
                .subtract(const Duration(days: 30))
                .toIso8601String(),
          },
        ],
        'payments': [
          {
            'id': 'mock_payment_1',
            'order_id': 'mock_order_1',
            'title': 'Эвакуация · Тверская',
            'amount': -2300,
            'status': 'completed',
            'created_at': DateTime.now()
                .subtract(const Duration(days: 6))
                .toIso8601String(),
          },
        ],
      };
    }

    if (path.endsWith('/cards')) {
      final number =
          body['card_number']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      final last4 =
          number.length >= 4 ? number.substring(number.length - 4) : '0000';
      return {
        'card': {
          'id': 'mock_card_$last4',
          'brand': number.startsWith('4') ? 'visa' : 'mastercard',
          'last4': last4,
          'exp_month': body['exp_month'] ?? 12,
          'exp_year': body['exp_year'] ?? 2028,
          'holder': body['holder'] ?? 'EVIK CLIENT',
          'is_default': true,
          'created_at': DateTime.now().toIso8601String(),
        },
      };
    }

    if (path.contains('/cards/') && path.endsWith('/default')) {
      return {
        'card': {
          'id': path.split('/')[4],
          'brand': 'visa',
          'last4': '4242',
          'exp_month': 12,
          'exp_year': 2027,
          'holder': 'EVIK CLIENT',
          'is_default': true,
          'created_at': DateTime.now().toIso8601String(),
        },
      };
    }

    if (path.contains('/cards/')) {
      return {'deleted': true};
    }

    if (path.endsWith('/promocode/apply')) {
      return {
        'promocode': {
          'code': body['code'] ?? 'EVIK2025',
          'description': 'Скидка 10% на следующую поездку',
          'discount_pct': 10,
        },
      };
    }

    return {'success': true};
  }

  Map<String, dynamic> _generateMockUser({String role = 'client'}) {
    return {
      'id': _mockUserId,
      'phone': '+7999123456${_random.nextInt(10)}',
      'name': role == 'driver' ? 'Тестовый Водитель' : 'Тестовый Пользователь',
      'role': role,
      'rating': 4.5 + _random.nextDouble() * 0.5,
      'totalOrders': _random.nextInt(50) + 1,
      'createdAt': DateTime.now()
          .subtract(Duration(days: _random.nextInt(365)))
          .toIso8601String(),
    };
  }

  Map<String, dynamic> _generateMockDriver() {
    final isApproved = _random.nextBool();
    return {
      'id': _mockDriverId,
      'userId': _mockUserId,
      'name': 'Тестовый Водитель',
      'phone': '+7999654321${_random.nextInt(10)}',
      'rating': 4.0 + _random.nextDouble() * 1.0,
      'completedOrders': _random.nextInt(200) + 10,
      'vehicle': {
        'type': ['light', 'suv', 'minibus', 'truck'][_random.nextInt(4)],
        'model': 'Toyota Hiace',
        'number': 'А${_random.nextInt(999)}АА 77',
        'color': 'Белый',
      },
      'isOnline': _random.nextBool(),
      'isApproved': isApproved,
      'status':
          isApproved ? 'approved' : ['pending', 'rejected'][_random.nextInt(2)],
      'location': {
        'lat': AppConstants.moscowLat + (_random.nextDouble() - 0.5) * 0.1,
        'lng': AppConstants.moscowLng + (_random.nextDouble() - 0.5) * 0.1,
      },
      'documents': {
        'passport': isApproved,
        'license': isApproved,
        'vehicleDocs': isApproved,
        'selfie': isApproved,
      },
    };
  }

  Map<String, dynamic> _generateMockOrder({String status = 'searching'}) {
    final pickupLat =
        AppConstants.moscowLat + (_random.nextDouble() - 0.5) * 0.05;
    final pickupLng =
        AppConstants.moscowLng + (_random.nextDouble() - 0.5) * 0.05;
    final dropoffLat =
        AppConstants.moscowLat + (_random.nextDouble() - 0.5) * 0.05;
    final dropoffLng =
        AppConstants.moscowLng + (_random.nextDouble() - 0.5) * 0.05;

    return {
      'id': _mockOrderId,
      'clientId': _mockUserId,
      'driverId': status != 'searching' ? _mockDriverId : null,
      'status': status,
      'vehicleType': ['light', 'suv', 'minibus', 'truck'][_random.nextInt(4)],
      'pickupLocation': {
        'lat': pickupLat,
        'lng': pickupLng,
        'address': 'Тестовая улица, 1',
      },
      'dropoffLocation': {
        'lat': dropoffLat,
        'lng': dropoffLng,
        'address': 'Тестовая улица, 100',
      },
      'price': (800 + _random.nextInt(2000)).toDouble(),
      'distance': (5 + _random.nextInt(45)).toDouble(),
      'estimatedTime': _random.nextInt(60) + 15,
      'createdAt': DateTime.now().toIso8601String(),
      'driver': status != 'searching'
          ? {
              'id': _mockDriverId,
              'name': 'Тестовый Водитель',
              'phone': '+79996543210',
              'rating': 4.5,
              'vehicle': {
                'model': 'Toyota Hiace',
                'number': 'А123АА 77',
                'color': 'Белый',
              },
              'location': {
                'lat': pickupLat + (_random.nextDouble() - 0.5) * 0.01,
                'lng': pickupLng + (_random.nextDouble() - 0.5) * 0.01,
              },
            }
          : null,
    };
  }

  List<Map<String, dynamic>> _generateMockAvailableOrders() {
    final count = _random.nextInt(5) + 1;
    return List.generate(count, (index) => _generateMockOrder());
  }

  Map<String, dynamic> _generateMockActiveOrder() {
    final statuses = ['assigned', 'onWay', 'arrived', 'evacuating'];
    return _generateMockOrder(
        status: statuses[_random.nextInt(statuses.length)]);
  }

  List<Map<String, dynamic>> _generateMockOrderHistory() {
    final count = _random.nextInt(10) + 3;
    return List.generate(count, (index) {
      final statuses = ['completed', 'cancelled'];
      return _generateMockOrder(
          status: statuses[_random.nextInt(statuses.length)]);
    });
  }

  Map<String, dynamic> _generateMockEarnings() {
    final today = (500 + _random.nextInt(1500)).toDouble();
    final week = today * (5 + _random.nextInt(3));
    final month = week * (3 + _random.nextInt(2));

    return {
      'today': today,
      'thisWeek': week,
      'thisMonth': month,
      'totalOrders': _random.nextInt(200) + 10,
      'averageRating': 4.0 + _random.nextDouble() * 1.0,
      'onlineTime': Duration(hours: _random.nextInt(12) + 4).inMinutes,
    };
  }
}

// Оригинальный HTTP клиент
class HttpApiClient implements ApiClient {
  HttpApiClient({required String baseUrl}) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _baseUri.resolve(path);
    final response = await http.get(uri, headers: headers);
    return _decodeResponse('GET', path, uri, response);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final uri = _baseUri.resolve(path);
    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        ...?headers,
      },
      body: jsonEncode(body),
    );
    return _decodeResponse('POST', path, uri, response);
  }

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _baseUri.resolve(path);
    final response = await http.delete(uri, headers: headers);
    return _decodeResponse('DELETE', path, uri, response);
  }

  Map<String, dynamic> _decodeResponse(
    String method,
    String path,
    Uri uri,
    http.Response response,
  ) {
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString() ?? response.body
          : response.body;
      throw ApiClientException(
        method: method,
        path: path,
        statusCode: response.statusCode,
        message: message,
        uri: uri,
      );
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }
}
