import 'dart:convert';

import '../auth/token_storage.dart';
import '../config/server_config.dart';

/// Builds the [ReadCache] scope: `<server public URL>#<account id>`, so
/// each account on each self-hosted server has its own cache entries.
///
/// Reads only local storage — never the network — so cached data stays
/// reachable offline and after the session token expires. Returns `null`
/// with no server configured or no stored session.
Future<String?> Function() accountCacheScope({
  required ServerConfigStorage serverConfigStorage,
  required TokenStorage tokenStorage,
}) {
  return () async {
    final config = await serverConfigStorage.read();
    if (config == null) return null;
    final session = await tokenStorage.read();
    if (session == null) return null;
    final accountId = jwtAccountId(session.token);
    if (accountId == null) return null;
    return '${config.publicUrl}#$accountId';
  };
}

/// The `id` claim of a Trek session JWT (the user's numeric id, signed in
/// `AuthService.generateToken` server-side), or `null` if [token] isn't a
/// JWT carrying one.
String? jwtAccountId(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map<String, dynamic>) return null;
    final id = payload['id'];
    if (id is int || (id is String && id.isNotEmpty)) return '$id';
    return null;
  } on FormatException {
    return null;
  }
}
