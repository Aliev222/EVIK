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
  Future<Map<String, dynamic>> get(String path) async {
    final client = HttpClient();
    try {
      final uri = _baseUri.resolve(path);
      final request = await client.getUrl(uri);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return _decodeResponse('GET', path, uri, response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

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
      return _decodeResponse('POST', path, uri, response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeResponse(
    String method,
    String path,
    Uri uri,
    int statusCode,
    String text,
  ) {
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);

    if (statusCode < 200 || statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString() ?? text
          : text;
      throw HttpException(
        '$method $path failed with $statusCode: $message',
        uri: uri,
      );
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }
}
