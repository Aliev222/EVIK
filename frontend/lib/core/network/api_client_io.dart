import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

ApiClient createPlatformApiClient({String baseUrl = defaultApiBaseUrl}) {
  return IoApiClient(baseUrl: baseUrl);
}

class IoApiClient implements ApiClient {
  IoApiClient({required String baseUrl}) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final uri = _baseUri.resolve(path);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map<String, dynamic>
            ? decoded['error']?.toString() ?? text
            : text;
        throw HttpException(
          'POST $path failed with ${response.statusCode}: $message',
          uri: uri,
        );
      }

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }
}
