import 'dart:convert';
import 'package:http/http.dart' as http;

class SimpleAuthService {
  static const String baseUrl = 'https://tow-truck.onrender.com/api/v1';

  // Регистрация без SMS
  static Future<Map<String, dynamic>> register({
    required String phone,
    required String name,
    required String password,
    required String role, // "client" или "driver"
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'name': name,
        'password': password,
        'role': role,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw SimpleAuthException(error['message'] ?? 'Registration failed');
    }
  }

  // Вход с номером телефона + пароль
  static Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    // Для login используем phone как user_id
    final userId = phone.replaceAll('+', '').replaceAll(' ', '').replaceAll('-', '');

    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'role': 'client', // Попробуем как клиент, потом можно будет определять роль
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw SimpleAuthException(error['message'] ?? 'Login failed');
    }
  }

  // Обновление токена
  static Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'refresh_token': refreshToken,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw SimpleAuthException('Token refresh failed');
    }
  }

  // Нормализация номера телефона
  static String normalizePhone(String phone) {
    String normalized = phone.trim();

    // Убираем все лишние символы
    normalized = normalized.replaceAll(RegExp(r'[^\d+]'), '');

    // Добавляем +7 если нужно
    if (normalized.startsWith('8')) {
      normalized = '+7${normalized.substring(1)}';
    } else if (normalized.startsWith('7')) {
      normalized = '+$normalized';
    } else if (!normalized.startsWith('+')) {
      normalized = '+7$normalized';
    }

    return normalized;
  }

  // Валидация номера телефона
  static bool isValidPhone(String phone) {
    final normalized = normalizePhone(phone);
    return RegExp(r'^\+7\d{10}$').hasMatch(normalized);
  }
}

class SimpleAuthException implements Exception {
  final String message;
  SimpleAuthException(this.message);

  @override
  String toString() => 'SimpleAuthException: $message';
}