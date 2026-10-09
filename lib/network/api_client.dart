import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

enum HttpMethod { get, post, put, patch, delete }

/// Result of [ApiClient.getIfChanged]: either a fresh body or confirmation
/// that the caller's copy is still current.
sealed class ConditionalResponse {
  const ConditionalResponse();
}

/// The server sent a (new) representation. [etag] is the response's `ETag`
/// header, if any — Trek's Express server attaches a weak ETag to every
/// JSON response.
class Modified extends ConditionalResponse {
  const Modified(this.body, this.etag);

  final dynamic body;
  final String? etag;
}

/// The server answered 304 Not Modified: the representation identified by
/// the `If-None-Match` ETag is still current.
class NotModified extends ConditionalResponse {
  const NotModified();
}

/// Thin wrapper around [http.Client] that centralizes base-URL resolution,
/// auth-header injection, JSON encoding/decoding, and error mapping so
/// feature code never touches raw HTTP concerns directly.
///
/// Exactly one of [baseUrl] (fixed) or [getBaseUrl] (resolved fresh before
/// every request — e.g. to switch between a private/public server URL based
/// on the current Wi-Fi network) must be provided.
///
/// [getAccessToken] is called before every request to attach a bearer token,
/// if present. [onUnauthorized] is invoked at most once per request when the
/// server responds 401 — return `true` to retry the request once (e.g. after
/// refreshing the token) or `false` to let the [UnauthorizedException]
/// propagate.
class ApiClient {
  ApiClient({
    String? baseUrl,
    Future<String> Function()? getBaseUrl,
    http.Client? httpClient,
    Future<String?> Function()? getAccessToken,
    Future<bool> Function()? onUnauthorized,
    Duration timeout = const Duration(seconds: 15),
  }) : assert(
         baseUrl != null || getBaseUrl != null,
         'ApiClient requires either baseUrl or getBaseUrl.',
       ),
       _baseUrl = baseUrl,
       _getBaseUrl = getBaseUrl,
       _httpClient = httpClient ?? http.Client(),
       _getAccessToken = getAccessToken,
       _onUnauthorized = onUnauthorized,
       _timeout = timeout;

  final String? _baseUrl;
  final Future<String> Function()? _getBaseUrl;
  final http.Client _httpClient;
  final Future<String?> Function()? _getAccessToken;
  final Future<bool> Function()? _onUnauthorized;
  final Duration _timeout;

  Future<String> _resolveBaseUrl() =>
      _getBaseUrl?.call() ?? Future.value(_baseUrl!);

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(HttpMethod.get, path, query: query);

  /// Conditional GET: sends [etag] as `If-None-Match` (when non-null) and
  /// returns [NotModified] on a 304 instead of re-downloading the body.
  /// Errors map exactly as for [get].
  Future<ConditionalResponse> getIfChanged(
    String path, {
    Map<String, dynamic>? query,
    String? etag,
  }) async {
    final response = await _request(
      HttpMethod.get,
      path,
      query: query,
      extraHeaders: etag == null ? null : {'If-None-Match': etag},
    );
    if (response.statusCode == 304) return const NotModified();
    return Modified(_decode(response), response.headers['etag']);
  }

  Future<dynamic> post(String path, {Object? body}) =>
      _send(HttpMethod.post, path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send(HttpMethod.put, path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(HttpMethod.patch, path, body: body);

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(HttpMethod.delete, path, body: body);

  Future<dynamic> _send(
    HttpMethod method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _decode(await _request(method, path, body: body, query: query));

  /// Sends the request (retrying once after a 401 if `onUnauthorized` says
  /// so) and returns the raw response, mapping transport failures to
  /// [NetworkException].
  Future<http.Response> _request(
    HttpMethod method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? extraHeaders,
    bool isRetry = false,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
    );

    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = await _getAccessToken?.call();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extraHeaders != null) headers.addAll(extraHeaders);

    final encodedBody = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      response = await _dispatch(
        method,
        uri,
        headers,
        encodedBody,
      ).timeout(_timeout);
    } on TimeoutException {
      throw const NetworkException();
    } on SocketException {
      throw const NetworkException('No internet connection.');
    } on http.ClientException {
      throw const NetworkException();
    }

    if (response.statusCode == 401 && !isRetry && _onUnauthorized != null) {
      final shouldRetry = await _onUnauthorized();
      if (shouldRetry) {
        return _request(
          method,
          path,
          body: body,
          query: query,
          extraHeaders: extraHeaders,
          isRetry: true,
        );
      }
    }

    return response;
  }

  Future<http.Response> _dispatch(
    HttpMethod method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    switch (method) {
      case HttpMethod.get:
        return _httpClient.get(uri, headers: headers);
      case HttpMethod.post:
        return _httpClient.post(uri, headers: headers, body: body);
      case HttpMethod.put:
        return _httpClient.put(uri, headers: headers, body: body);
      case HttpMethod.patch:
        return _httpClient.patch(uri, headers: headers, body: body);
      case HttpMethod.delete:
        return _httpClient.delete(uri, headers: headers, body: body);
    }
  }

  dynamic _decode(http.Response response) {
    final statusCode = response.statusCode;
    final decodedBody = response.body.isEmpty
        ? null
        : jsonDecode(response.body);

    if (statusCode >= 200 && statusCode < 300) {
      return decodedBody;
    }

    final message =
        _extractMessage(decodedBody) ??
        'Request failed with status $statusCode.';
    final code = _extractCode(decodedBody);

    switch (statusCode) {
      case 401:
        throw UnauthorizedException(message, code);
      case 403:
        throw ForbiddenException(message, code);
      case 400:
      case 422:
        throw ValidationException(message, code);
      default:
        throw ServerException(statusCode, message);
    }
  }

  /// Trek's error responses use `{ error: string, code?: string }`, not
  /// `{ message: string }` — the latter is checked too, for forward
  /// compatibility with any endpoint that doesn't follow the convention.
  String? _extractMessage(dynamic decodedBody) {
    if (decodedBody is Map<String, dynamic>) {
      final value = decodedBody['error'] ?? decodedBody['message'];
      if (value is String) return value;
    }
    return null;
  }

  String? _extractCode(dynamic decodedBody) {
    if (decodedBody is Map<String, dynamic> && decodedBody['code'] is String) {
      return decodedBody['code'] as String;
    }
    return null;
  }

  /// Releases the underlying HTTP client's resources.
  void close() => _httpClient.close();
}
