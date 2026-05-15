import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

ApiClient createPlatformApiClient({String baseUrl = defaultApiBaseUrl}) {
  return HttpApiClient(baseUrl: baseUrl);
}

class HttpApiClient implements ApiClient {
  HttpApiClient({required String baseUrl}) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;
  static const Duration _timeout = Duration(seconds: 30);

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) {
    return _makeRequest('GET', path, null, headers);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) {
    return _makeRequest('POST', path, body, headers);
  }

  @override
  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) {
    return _makeRequest('PUT', path, body, headers);
  }

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) {
    return _makeRequest('DELETE', path, null, headers);
  }

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  ) async {
    final uri = _baseUri.resolve(path);
    final requestHeaders = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    };

    late http.Response response;
    try {
      response = switch (method) {
        'GET' => await http.get(uri, headers: requestHeaders).timeout(_timeout),
        'POST' => await http
            .post(
              uri,
              headers: requestHeaders,
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(_timeout),
        'PUT' => await http
            .put(
              uri,
              headers: requestHeaders,
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(_timeout),
        'DELETE' =>
          await http.delete(uri, headers: requestHeaders).timeout(_timeout),
        _ => throw StateError('Unsupported HTTP method: $method'),
      };
    } on TimeoutException {
      throw ApiClientException(
        method: method,
        path: path,
        statusCode: 408,
        message: 'Превышено время ожидания ответа',
        uri: uri,
      );
    }

    return _decodeResponse(
        method, path, uri, response.statusCode, response.body);
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
      var errorMessage = 'Ошибка сети';
      if (decoded is Map<String, dynamic>) {
        final serverError = decoded['error']?.toString();
        if (serverError != null && serverError.isNotEmpty) {
          errorMessage = serverError;
        }
      }

      throw ApiClientException(
        method: method,
        path: path,
        statusCode: statusCode,
        message: errorMessage,
        uri: uri,
      );
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }
}
