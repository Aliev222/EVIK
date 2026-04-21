import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/map/data/yandex_map_provider.dart';
import '../../features/order/data/datasource/order_remote_datasource.dart';
import '../../features/order/data/repository_impl/order_repository_impl.dart';
import '../../features/order/domain/repositories/order_repository.dart';
import '../../features/order/presentation/state/order_state_notifier.dart';
import '../map/map_provider.dart';
import '../network/api_client.dart';
import '../network/api_client_stub.dart'
    if (dart.library.io) '../network/api_client_io.dart';
import '../realtime/event_dispatcher.dart';
import '../realtime/websocket_client.dart';
import '../realtime/websocket_client_stub.dart'
    if (dart.library.io) '../realtime/websocket_client_io.dart';
import '../storage/key_value_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return createPlatformApiClient();
});

final keyValueStorageProvider = Provider<KeyValueStorage>((ref) {
  return InMemoryKeyValueStorage();
});

final mapProviderProvider = Provider<MapProvider>((ref) {
  if (kIsWeb) {
    return StubMapProvider();
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return YandexMapProvider();
  }
  return StubMapProvider();
});

final webSocketClientProvider = Provider<WebSocketClient>((ref) {
  return createPlatformWebSocketClient();
});

final appEventDispatcherProvider = Provider<EventDispatcher>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return WsEventDispatcher(client: client, wsUrl: defaultWsUrl);
});

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return HttpOrderRemoteDataSource(apiClient: apiClient);
});

final appOrderRepositoryProvider = Provider<OrderRepository>((ref) {
  final remote = ref.watch(orderRemoteDataSourceProvider);
  return OrderRepositoryImpl(remote: remote);
});

List<Override> buildAppOverrides() {
  return <Override>[
    orderRepositoryProvider.overrideWith((ref) => ref.watch(appOrderRepositoryProvider)),
    eventDispatcherProvider.overrideWith((ref) => ref.watch(appEventDispatcherProvider)),
  ];
}
