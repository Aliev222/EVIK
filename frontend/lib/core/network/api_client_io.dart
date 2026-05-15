import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

ApiClient createPlatformApiClient({String baseUrl = defaultApiBaseUrl}) {
  return IoApiClient(baseUrl: baseUrl);
}

class IoApiClient implements ApiClient {
  IoApiClient({required String baseUrl}) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;
  static const Duration _timeout = Duration(seconds: 30);

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    return _makeRequest('GET', path, null, headers);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    return _makeRequest('POST', path, body, headers);
  }

  @override
  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    return _makeRequest('PUT', path, body, headers);
  }

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    return _makeRequest('DELETE', path, null, headers);
  }

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  ) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient();
        client.connectionTimeout = _timeout;

        try {
          final uri = _baseUri.resolve(path);
          late HttpClientRequest request;

          if (method == 'GET') {
            request = await client.getUrl(uri);
          } else if (method == 'POST') {
            request = await client.postUrl(uri);
          } else if (method == 'PUT') {
            request = await client.putUrl(uri);
          } else if (method == 'DELETE') {
            request = await client.deleteUrl(uri);
          }

          _applyHeaders(request, headers);
          if (method == 'POST' || method == 'PUT') {
            request.headers.contentType = ContentType.json;
            if (body != null) {
              request.write(jsonEncode(body));
            }
          }

          final response = await request.close().timeout(_timeout);
          final responseText = await response.transform(utf8.decoder).join();

          return _decodeResponse(
              method, path, uri, response.statusCode, responseText);
        } finally {
          client.close(force: true);
        }
      } on TimeoutException {
        if (attempt == maxRetries) {
          throw ApiClientException(
            method: method,
            path: path,
            statusCode: 408,
            message: 'Превышено время ожидания ответа',
            uri: _baseUri.resolve(path),
          );
        }
        await Future.delayed(Duration(seconds: attempt));
      } on SocketException {
        if (attempt == maxRetries) {
          throw ApiClientException(
            method: method,
            path: path,
            statusCode: 0,
            message: 'Нет подключения к интернету',
            uri: _baseUri.resolve(path),
          );
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    throw Exception('Unexpected error in _makeRequest');
  }

  void _applyHeaders(HttpClientRequest request, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return;
    }
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
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
      String errorMessage = 'Ошибка сети';

      switch (statusCode) {
        case 401:
          errorMessage = 'Ошибка авторизации';
          break;
        case 403:
          errorMessage = 'Доступ запрещен';
          break;
        case 404:
          errorMessage = 'Ресурс не найден';
          break;
        case 429:
          errorMessage = 'Слишком много запросов. Попробуйте позже';
          break;
        case 500:
          errorMessage = 'Ошибка сервера. Попробуйте позже';
          break;
        case 503:
          errorMessage = 'Сервис временно недоступен';
          break;
      }

      // Если есть детали ошибки от сервера
      if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
        final serverError = decoded['error'].toString();
        if (serverError.isNotEmpty && serverError != 'null') {
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
