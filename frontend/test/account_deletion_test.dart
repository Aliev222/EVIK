import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/storage/key_value_storage.dart';
import 'package:tow_truck_frontend/features/account/data/account_repository.dart';
import 'package:tow_truck_frontend/features/account/presentation/providers/account_deletion_provider.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/shared/widgets/account_settings_tiles.dart';

class _FakeApiClient implements ApiClient {
  _FakeApiClient({this.onDelete});

  Future<void> Function(String path, Map<String, String>? headers)? onDelete;
  String? lastDeletePath;
  Map<String, String>? lastDeleteHeaders;

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    lastDeletePath = path;
    lastDeleteHeaders = headers;
    final handler = onDelete;
    if (handler != null) {
      await handler(path, headers);
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(Ref ref)
      : super(
          api: BackendAuthApi(apiClient: _FakeApiClient()),
          storage: InMemoryKeyValueStorage(),
          ref: ref,
        );

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    state = state.copyWith(
      user: null,
      clearAccessToken: true,
      clearPendingAuth: true,
    );
  }
}

class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: const [
            LegalLinksTile(
              backgroundColor: Colors.white,
              textPrimaryColor: Colors.black,
              textSecondaryColor: Colors.grey,
              iconColor: Colors.orange,
            ),
            DeleteAccountEntry(
              backgroundColor: Colors.white,
              destructiveColor: Colors.red,
              warningMessage: 'Аккаунт будет удалён без возможности '
                  'восстановления. Это действие необратимо.',
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late ProviderContainer container;
  late _FakeApiClient apiClient;
  late _FakeAuthNotifier authNotifier;

  ProviderContainer buildContainer() {
    apiClient = _FakeApiClient();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          authNotifier = _FakeAuthNotifier(ref);
          return authNotifier;
        }),
        accountRepositoryProvider.overrideWithValue(
          AccountRepository(apiClient: apiClient, accessToken: 'test-token'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authProvider);
    return container;
  }

  Future<void> pumpHarness(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const _Harness(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('links are shown on the settings card', (tester) async {
    final c = buildContainer();
    await pumpHarness(tester, c);

    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    expect(find.text('Условия использования'), findsOneWidget);
    expect(find.text('Удалить аккаунт'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation does not call the API',
      (tester) async {
    final c = buildContainer();
    await pumpHarness(tester, c);

    await tester.tap(find.text('Удалить аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('Отмена'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(apiClient.lastDeletePath, isNull);
    expect(authNotifier.signOutCalls, 0);
  });

  testWidgets('confirming deletes the account and signs out',
      (tester) async {
    final c = buildContainer();
    await pumpHarness(tester, c);

    await tester.tap(find.text('Удалить аккаунт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(apiClient.lastDeletePath, '/api/v1/account');
    expect(
      apiClient.lastDeleteHeaders?['Authorization'],
      'Bearer test-token',
    );
    expect(find.text('Аккаунт удалён'), findsOneWidget);
    expect(authNotifier.signOutCalls, 1);
  });

  testWidgets('a 409 conflict shows the backend message without signing out',
      (tester) async {
    apiClient = _FakeApiClient(
      onDelete: (_, __) async {
        throw ApiClientException(
          method: 'DELETE',
          path: '/api/v1/account',
          statusCode: 409,
          message: 'Завершите активный заказ, чтобы удалить аккаунт',
          uri: Uri.parse('http://localhost/api/v1/account'),
        );
      },
    );
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          authNotifier = _FakeAuthNotifier(ref);
          return authNotifier;
        }),
        accountRepositoryProvider.overrideWithValue(
          AccountRepository(apiClient: apiClient, accessToken: 'test-token'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authProvider);
    await pumpHarness(tester, container);

    await tester.tap(find.text('Удалить аккаунт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(
      find.text('Завершите активный заказ, чтобы удалить аккаунт'),
      findsOneWidget,
    );
    expect(find.text('Не удалось удалить аккаунт'), findsOneWidget);
    expect(authNotifier.signOutCalls, 0);
  });
}