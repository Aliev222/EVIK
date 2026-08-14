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
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? headers}) =>
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
  Future<Map<String, dynamic>> delete(String path, {Map<String, String>? headers}) =>
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

  testWidgets('every code box advertises AutofillHints.oneTimeCode',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final editables =
        tester.widgetList<EditableText>(find.byType(EditableText));
    expect(editables.length, 6);
    for (final editable in editables) {
      expect(editable.autofillHints, const [AutofillHints.oneTimeCode]);
    }
  });

  testWidgets('pasting a full code fans out across the boxes and submits',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), '123456');
    await tester.pump(const Duration(milliseconds: 200));

    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    final joined = fields
        .map((f) => f.controller!.text)
        .toList()
        .join();
    expect(joined, '123456');
    expect(notifier.lastSentCode, '123456');
  });

  testWidgets('typing one digit auto-advances to the next box',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.pump();

    final node1 = tester
        .widget<EditableText>(find.byType(EditableText).at(1))
        .focusNode;
    expect(node1.hasFocus, isTrue);
  });

  testWidgets('backspace on an empty box returns focus to the previous box',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Fill box 1 (index 1) so focus auto-advances to box 2 (empty).
    await tester.enterText(find.byType(TextFormField).at(1), '4');
    await tester.pump();

    final node0 = tester
        .widget<EditableText>(find.byType(EditableText).at(0))
        .focusNode;
    final node1 = tester
        .widget<EditableText>(find.byType(EditableText).at(1))
        .focusNode;
    final node2 = tester
        .widget<EditableText>(find.byType(EditableText).at(2))
        .focusNode;
    expect(node2.hasFocus, isTrue);
    expect(node0.hasFocus, isFalse);

    // Backspace on the empty focused box must jump back to box 1.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(node1.hasFocus, isTrue);
    expect(node2.hasFocus, isFalse);
  });
}