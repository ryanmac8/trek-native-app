import 'dart:async';
import 'dart:convert';

import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/share_import/share_import_api.dart';
import 'package:trek/features/share_import/share_import_store.dart';
import 'package:trek/share_intake/share_intake.dart';

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

/// In-memory [ShareImportStore] fake — avoids the `shared_preferences`
/// platform channel.
class InMemoryShareImportStore implements ShareImportStore {
  final Map<String, List<ShareTargetTrip>> trips = {};
  List<PendingPlaceImport> pending = [];

  @override
  Future<List<ShareTargetTrip>?> readTrips(String serverUrl) async =>
      trips[serverUrl];

  @override
  Future<void> writeTrips(
    String serverUrl,
    List<ShareTargetTrip> trips,
  ) async => this.trips[serverUrl] = List.of(trips);

  @override
  Future<List<PendingPlaceImport>> readPending() async => List.of(pending);

  @override
  Future<void> writePending(List<PendingPlaceImport> pending) async =>
      this.pending = List.of(pending);
}

/// [ShareIntake] fake driven by the test.
class FakeShareIntake implements ShareIntake {
  FakeShareIntake({this.initial});

  String? initial;
  final _controller = StreamController<String>.broadcast();

  void share(String text) => _controller.add(text);

  @override
  Future<String?> takeInitialShare() async {
    final value = initial;
    initial = null;
    return value;
  }

  @override
  Stream<String> get shares => _controller.stream;
}
