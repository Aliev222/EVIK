import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/auth/presentation/screens/sms_verification_screen.dart';

class _NoopApiClient implements ApiClient {
  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
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

class _SmsAuthNotifier extends AuthNotifier {
  _SmsAuthNotifier(Ref ref)
      : super(
          api: BackendAuthApi(apiClient: _NoopApiClient()),
          storage: InMemoryKeyValueStorage(),
          ref: ref,
        ) {
    state = state.copyWith(
      phoneNumber: '+7 (999) 123-45-67',
      pendingRole: UserRole.client,
      verificationId: 'backend-otp-pending',
      codeSentAt: DateTime.now(),
    );
  }

  String? lastSentCode;
  int resendCalls = 0;

  @override
  Future<void> verifySmsCode(String code) async {
    lastSentCode = code;
  }

  @override
  Future<void> resendSmsCode() async {
    resendCalls++;
  }
}

void main() {
  late _SmsAuthNotifier notifier;

  Widget harness() {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          notifier = _SmsAuthNotifier(ref);
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SmsVerificationScreen()),
    );
  }

  testWidgets('one code field advertises AutofillHints.oneTimeCode',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final editables =
        tester.widgetList<EditableText>(find.byType(EditableText));
    expect(editables, hasLength(1));
    expect(editables.single.autofillHints, const [AutofillHints.oneTimeCode]);
  });

  testWidgets('pasting a full code submits it from one input', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump(const Duration(milliseconds: 200));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '123456');
    expect(notifier.lastSentCode, '123456');
  });

  testWidgets('backspace removes the preceding digit in the same input',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12',
    );
  });
}
