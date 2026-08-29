import 'dart:convert';

import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/notifications/notifications_local_store.dart';
import 'package:trek/notifications/trek_notification.dart';

/// Builds a syntactically-valid, unsigned JWT string for tests — Trek's
/// backend is the only thing that verifies the signature; the client only
/// ever reads claims out of the payload.
String fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object part) =>
      base64Url.encode(utf8.encode(jsonEncode(part))).replaceAll('=', '');

  final header = encodeSegment({'alg': 'HS256', 'typ': 'JWT'});
  final body = encodeSegment(payload);
  return '$header.$body.signature';
}

/// In-memory [TokenStorage] fake — no platform channel involved, for tests
/// that need a real (non-mocked) `AuthService` wired to a widget tree.
class InMemoryTokenStorage implements TokenStorage {
  SessionToken? _token;

  @override
  Future<SessionToken?> read() async => _token;

  @override
  Future<void> write(SessionToken token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// [TokenStorage] fake that always throws on read — simulates
/// `flutter_secure_storage` failing (e.g. Keychain access after a backup
/// restore, Keystore invalidated by a biometric/lock-screen change).
class ThrowingTokenStorage implements TokenStorage {
  @override
  Future<SessionToken?> read() async {
    throw StateError('simulated secure storage failure');
  }

  @override
  Future<void> write(SessionToken token) async {}

  @override
  Future<void> clear() async {}
}

/// In-memory [ServerConfigStorage] fake — avoids the `shared_preferences`
/// platform channel in widget tests.
class InMemoryServerConfigStorage implements ServerConfigStorage {
  InMemoryServerConfigStorage({ServerConfig? initial}) : _config = initial;

  ServerConfig? _config;

  @override
  Future<ServerConfig?> read() async => _config;

  @override
  Future<void> write(ServerConfig config) async => _config = config;

  @override
  Future<void> clear() async => _config = null;
}

/// In-memory [NotificationsLocalStore] fake — avoids the
/// `shared_preferences` platform channel in repository/widget tests. Holds
/// the cached list and the pending-reads outbox, like the real store.
class InMemoryNotificationsLocalStore implements NotificationsLocalStore {
  InMemoryNotificationsLocalStore({
    List<TrekNotification> notifications = const [],
    Set<int> pendingReads = const {},
  }) : _notifications = List.of(notifications),
       _pendingReads = Set.of(pendingReads);

  List<TrekNotification> _notifications;
  Set<int> _pendingReads;

  @override
  Future<List<TrekNotification>> readNotifications() async =>
      List.of(_notifications);

  @override
  Future<void> writeNotifications(List<TrekNotification> notifications) async =>
      _notifications = List.of(notifications);

  @override
  Future<Set<int>> readPendingReads() async => Set.of(_pendingReads);

  @override
  Future<void> writePendingReads(Set<int> ids) async =>
      _pendingReads = Set.of(ids);
}
