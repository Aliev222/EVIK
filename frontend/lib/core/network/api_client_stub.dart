import 'api_client.dart';

ApiClient createPlatformApiClient({String baseUrl = defaultApiBaseUrl}) {
  return const NoOpApiClient();
}
