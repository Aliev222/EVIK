import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClientException implements Exception {
  final String message;
  final int? statusCode;

  ApiClientException(this.message, [this.statusCode]);
}

class UnauthorizedException extends ApiClientException {
  UnauthorizedException() : super('Unauthorized', 401);
}

class ApiClient {
  static const String baseUrl = 'http://localhost:5000/api/v1'; // TODO: use env config
  static const _storage = FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;

  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  // Initialize tokens from secure storage
  Future<void> init() async {
    _refreshToken = await _storage.read(key: 'refresh_token');
    if (_refreshToken != null) {
      await _refreshTokens();
    }
  }

  Future<Map<String, dynamic>> get(String endpoint) async {
    return _request('GET', endpoint);
  }

  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    return _request('POST', endpoint, body: body);
  }

  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> body) async {
    return _request('PUT', endpoint, body: body);
  }

  Future<Map<String, dynamic>> delete(String endpoint) async {
    return _request('DELETE', endpoint);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    bool isRetry = false,
  }) async {
    try {
      final response = await _makeRequest(method, endpoint, body: body);
      return _handleResponse(response);
    } on UnauthorizedException {
      if (!isRetry && _refreshToken != null) {
        await _refreshTokens();
        return _request(method, endpoint, body: body, isRetry: true);
      }
      rethrow;
    }
  }

  Future<http.Response> _makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };

    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        return http.put(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        throw ApiClientException('Unsupported method: $method');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiClientException(
        'HTTP Error ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }

    if (response.body.isEmpty) {
      return {};
    }

    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw ApiClientException('Invalid JSON response: ${response.body}');
    }
  }

  Future<void> _refreshTokens() async {
    if (_refreshToken == null) {
      throw UnauthorizedException();
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (response.statusCode == 401) {
        await clearTokens();
        throw UnauthorizedException();
      }

      final data = _handleResponse(response);
      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];

      // Store new refresh token securely
      await _storage.write(key: 'refresh_token', value: _refreshToken);

    } catch (e) {
      await clearTokens();
      rethrow;
    }
  }

  Future<void> setTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'refresh_token');
  }

  bool get isAuthenticated => _accessToken != null;
}