import 'dart:convert';

import 'package:trek/auth/biometric_auth_service.dart';
import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/days/day.dart';
import 'package:trek/days/days_local_store.dart';
import 'package:trek/features/trips/trip_dashboard_nav_layout_store.dart';
import 'package:trek/trips/trip.dart';
import 'package:trek/trips/trips_local_store.dart';

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

/// [BiometricAuthService] fake — avoids the `local_auth` platform channel,
/// which isn't mocked in widget tests and hangs `pumpAndSettle` if hit.
/// Defaults to unavailable (skips the lock screen), matching most tests'
/// needs; construct with `available: true` for lock-screen-specific tests.
class FakeBiometricAuthService implements BiometricAuthService {
  FakeBiometricAuthService({
    this.available = false,
    this.authenticateResult = true,
  });

  final bool available;
  final bool authenticateResult;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async => authenticateResult;
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

/// In-memory [TripsLocalStore] fake — avoids the `shared_preferences`
/// platform channel in widget/repository tests.
class InMemoryTripsLocalStore implements TripsLocalStore {
  InMemoryTripsLocalStore({
    List<Trip> initial = const [],
    Set<int> pendingDeletes = const {},
  }) : _trips = List.of(initial),
       _pendingDeletes = Set.of(pendingDeletes);

  List<Trip> _trips;
  Set<int> _pendingDeletes;

  @override
  Future<List<Trip>> read() async => List.of(_trips);

  @override
  Future<void> write(List<Trip> trips) async => _trips = List.of(trips);

  @override
  Future<Set<int>> readPendingDeletes() async => Set.of(_pendingDeletes);

  @override
  Future<void> writePendingDeletes(Set<int> ids) async =>
      _pendingDeletes = Set.of(ids);
}

/// In-memory [DaysLocalStore] fake — avoids the `shared_preferences`
/// platform channel in widget/repository tests. Keyed per trip id, like the
/// real store.
class InMemoryDaysLocalStore implements DaysLocalStore {
  InMemoryDaysLocalStore({Map<String, List<Day>> initial = const {}})
    : _daysByTripId = {
        for (final entry in initial.entries) entry.key: List.of(entry.value),
      };

  final Map<String, List<Day>> _daysByTripId;

  @override
  Future<List<Day>> read(String tripId) async =>
      List.of(_daysByTripId[tripId] ?? const []);

  @override
  Future<void> write(String tripId, List<Day> days) async =>
      _daysByTripId[tripId] = List.of(days);
}

/// In-memory [TripDashboardNavLayoutStore] fake — avoids the
/// `shared_preferences` platform channel in widget tests.
class InMemoryTripDashboardNavLayoutStore
    implements TripDashboardNavLayoutStore {
  InMemoryTripDashboardNavLayoutStore({List<String?>? initial})
    : _slotKeys = initial;

  List<String?>? _slotKeys;

  @override
  Future<List<String?>?> read() async =>
      _slotKeys == null ? null : List.of(_slotKeys!);

  @override
  Future<void> write(List<String?> slotKeys) async =>
      _slotKeys = List.of(slotKeys);
}
