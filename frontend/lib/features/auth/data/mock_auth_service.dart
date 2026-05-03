import 'dart:async';

class MockAuthService {
  static const mockUser = {
    "id": "user_test_123",
    "phone": "+79123456789",
    "role": "client"
  };

  static const mockDriver = {
    "id": "driver_test_456",
    "phone": "+79123456780",
    "role": "driver"
  };

  // Simulate send SMS API call
  Future<Map<String, dynamic>> sendSms(String phone) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock successful response
    return {
      "verification_id": "test_verification_${DateTime.now().millisecondsSinceEpoch}",
      "expires_at": DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
    };
  }

  // Simulate verify SMS API call
  Future<Map<String, dynamic>> verifySms({
    required String verificationId,
    required String code,
    required String phone,
    required String fullName,
    required String role,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Simulate code validation (accept 1234 as valid)
    if (code != "1234") {
      throw MockAuthException("Invalid verification code", 401);
    }

    // Return appropriate user based on role
    final user = role == "driver"
      ? Map<String, dynamic>.from(mockDriver)
      : Map<String, dynamic>.from(mockUser);

    user["phone"] = phone;

    return {
      "access_token": "mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}",
      "refresh_token": "mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}",
      "expires_at": DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      "user": user,
    };
  }

  // Simulate refresh token API call
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    await Future.delayed(const Duration(milliseconds: 300));

    return {
      "access_token": "new_mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}",
      "refresh_token": "new_mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}",
      "expires_at": DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    };
  }

  // Simulate get current user API call
  Future<Map<String, dynamic>> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 400));

    return {
      "user": mockUser,
    };
  }
}

class MockAuthException implements Exception {
  final String message;
  final int statusCode;

  MockAuthException(this.message, this.statusCode);

  @override
  String toString() => 'MockAuthException($statusCode): $message';
}