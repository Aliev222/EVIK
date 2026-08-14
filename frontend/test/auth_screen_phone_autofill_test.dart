import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/features/auth/presentation/auth_screen.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

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

class _AuthNotifier extends AuthNotifier {
  _AuthNotifier(Ref ref)
      : super(
          api: BackendAuthApi(apiClient: _NoopApiClient()),
          storage: InMemoryKeyValueStorage(),
          ref: ref,
        );
}

void main() {
  testWidgets('phone field advertises AutofillHints.telephoneNumber',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _AuthNotifier(ref)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AuthScreen()),
    ));
    await tester.pump();

    final editables = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(editables, hasLength(1));
    expect(
      editables.single.autofillHints,
      contains(AutofillHints.telephoneNumber),
    );
  });
}