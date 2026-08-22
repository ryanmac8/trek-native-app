import 'dart:convert';

import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/todos/todo_item.dart';
import 'package:trek/todos/todo_local_store.dart';

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

/// In-memory [TodoLocalStore] fake — avoids the `shared_preferences`
/// platform channel in widget/repository tests. Keyed per trip id, like the
/// real store.
class InMemoryTodoLocalStore implements TodoLocalStore {
  InMemoryTodoLocalStore({Map<String, List<TodoItem>> initial = const {}})
    : _itemsByTripId = {
        for (final entry in initial.entries) entry.key: List.of(entry.value),
      };

  final Map<String, List<TodoItem>> _itemsByTripId;
  final Set<String> _reorderPendingTripIds = {};

  @override
  Future<List<TodoItem>> read(String tripId) async =>
      List.of(_itemsByTripId[tripId] ?? const []);

  @override
  Future<void> write(String tripId, List<TodoItem> items) async =>
      _itemsByTripId[tripId] = List.of(items);

  @override
  Future<bool> readReorderPending(String tripId) async =>
      _reorderPendingTripIds.contains(tripId);

  @override
  Future<void> writeReorderPending(String tripId, bool pending) async {
    if (pending) {
      _reorderPendingTripIds.add(tripId);
    } else {
      _reorderPendingTripIds.remove(tripId);
    }
  }
}
