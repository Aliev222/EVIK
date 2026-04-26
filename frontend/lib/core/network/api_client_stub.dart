import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

ApiClient createPlatformApiClient({String baseUrl = defaultApiBaseUrl}) {
  return HttpApiClient(baseUrl: baseUrl);
}

class HttpApiClient implements ApiClient {
  HttpApiClient({required String baseUrl}) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _baseUri.resolve(path);
    final response = await http.get(uri, headers: headers);
    return _decodeResponse('GET', path, uri, response);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final uri = _baseUri.resolve(path);
    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        ...?headers,
      },
      body: jsonEncode(body),
    );
    return _decodeResponse('POST', path, uri, response);
  }

  Map<String, dynamic> _decodeResponse(
    String method,
    String path,
    Uri uri,
    http.Response response,
  ) {
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString() ?? response.body
          : response.body;
      throw ApiClientException(
        method: method,
        path: path,
        statusCode: response.statusCode,
        message: message,
        uri: uri,
      );
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }
}
