import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

/// Records every API call and serves canned auth responses so the phone-only
/// registration flow can be asserted end to end without a network.
class _RecordingApiClient implements ApiClient {
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    posts.add({'path': path, 'body': body});
    if (path == '/api/v1/auth/otp/request') {
      return <String, dynamic>{'otp_required': true, 'expires_in_seconds': 600};
    }
    if (path == '/api/v1/auth/otp/verify') {
      final phone = body['phone']?.toString() ?? '';
      return <String, dynamic>{
        'tokens': <String, dynamic>{
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
        },
        'user': <String, dynamic>{
          'id': 'u12345',
          'role': body['role']?.toString() ?? 'client',
          'phone': phone,
          // The backend stores the phone as the display name for a client.
          'full_name': phone,
        },
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> delete(String path,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();
}

void main() {
  late _RecordingApiClient api;

  (AuthNotifier, ProviderContainer) buildHarness() {
    api = _RecordingApiClient();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          return AuthNotifier(
            api: BackendAuthApi(apiClient: api),
            storage: InMemoryKeyValueStorage(),
            ref: ref,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(authProvider.notifier);
    return (notifier, container);
  }

  test('sign-in requests an OTP with phone+role and never a name', () async {
    final (notifier, _) = buildHarness();
    await notifier.signInWithPhone('+7 (999) 123-45-67');

    final otpRequest = api.posts.firstWhere(
      (p) => p['path'] == '/api/v1/auth/otp/request',
    );
    final body = jsonDecode(jsonEncode(otpRequest['body'])) as Map;
    expect(body['phone'], '+79991234567');
    expect(body['role'], 'client');
    expect(body.containsKey('full_name'), isFalse);
    expect(notifier.state.phoneNumber, '+79991234567');
  });

  test('OTP verify has no full_name and the client identity is the phone',
      () async {
    final (notifier, _) = buildHarness();
    await notifier.signInWithPhone('+79991234567');

    await notifier.verifySmsCode('123456');

    final verifyRequest = api.posts.firstWhere(
      (p) => p['path'] == '/api/v1/auth/otp/verify',
    );
    final body = jsonDecode(jsonEncode(verifyRequest['body'])) as Map;
    expect(body['phone'], '+79991234567');
    expect(body['role'], 'client');
    expect(body.containsKey('full_name'), isFalse);

    final user = notifier.state.user;
    expect(user, isNotNull);
    expect(user!.fullName, '+79991234567', reason: 'client identity = phone');
    expect(user.phone, '+79991234567');
    expect(notifier.state.isAuthenticated, isTrue);
  });

  test('client session state never fabricates a display name', () async {
    final (notifier, _) = buildHarness();
    await notifier.signInWithPhone('+79991234567');
    await notifier.verifySmsCode('123456');

    final user = notifier.state.user;
    expect(user, isNotNull);
    expect(user!.fullName.contains('User Name'), isFalse);
    expect(user.fullName.contains('Пользователь Авро'), isFalse);
  });
}