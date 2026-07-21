import 'package:http/http.dart' as http;

import '../network/api_client.dart';
import '../network/api_exception.dart';

/// Pings a candidate server URL's unauthenticated `/api/health` endpoint to
/// confirm it's actually reachable, before the user commits a private (LAN)
/// endpoint to `ServerConfig` — e.g. a typo'd IP, or a LAN address entered
/// while not actually on that network.
class ServerHealthCheck {
  ServerHealthCheck({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  /// Returns `true` if [baseUrl] responds to `GET /api/health`, `false` for
  /// any network failure or non-2xx response — never throws, since this is
  /// advisory (the caller decides whether to save the endpoint anyway).
  Future<bool> ping(String baseUrl) async {
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: _httpClient,
      timeout: const Duration(seconds: 6),
    );
    try {
      await client.get('/api/health');
      return true;
    } on ApiException {
      return false;
    }
  }
}
