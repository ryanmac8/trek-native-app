import 'dart:convert';

import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/notifications/notifications_local_store.dart';
import 'package:trek/notifications/trek_notification.dart';
import 'package:trek/transit/transit_local_store.dart';
import 'package:trek/transit/transit_models.dart';
import 'package:trek/weather/weather_local_store.dart';
import 'package:trek/weather/weather_models.dart';

/// Trip test helpers.
import '../features/trips/trip_models.dart';

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

/// In-memory [WeatherLocalStore] fake — avoids the `shared_preferences`
/// platform channel in repository/widget tests. [staleKeys] lets a test mark
/// specific entries as past their TTL so the offline-fallback path can be
/// exercised without waiting on a clock.
class InMemoryWeatherLocalStore implements WeatherLocalStore {
  final Map<String, WeatherReport> entries = {};
  final Set<String> staleKeys = {};

  @override
  Future<CachedWeather?> read(String key) async {
    final report = entries[key];
    if (report == null) return null;
    return CachedWeather(report: report, isFresh: !staleKeys.contains(key));
  }

  @override
  Future<void> write(String key, WeatherReport report) async {
    entries[key] = report;
    staleKeys.remove(key);
  }
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

/// In-memory [TransitLocalStore] fake — avoids the `shared_preferences`
/// platform channel in repository/widget tests. Each result kind is a plain
/// map keyed by the same normalised query string the real store uses; a
/// missing key reads as `null` (never fetched).
class InMemoryTransitLocalStore implements TransitLocalStore {
  final Map<String, List<TransitPlace>> stops = {};
  final Map<String, List<TransitItinerary>> plans = {};
  final Map<String, List<Airport>> airports = {};

  @override
  Future<List<TransitPlace>?> readStopSearch(String key) async => stops[key];

  @override
  Future<void> writeStopSearch(String key, List<TransitPlace> results) async =>
      stops[key] = results;

  @override
  Future<List<TransitItinerary>?> readRoutePlan(String key) async => plans[key];

  @override
  Future<void> writeRoutePlan(
    String key,
    List<TransitItinerary> itineraries,
  ) async => plans[key] = itineraries;

  @override
  Future<List<Airport>?> readAirportSearch(String key) async => airports[key];

  @override
  Future<void> writeAirportSearch(String key, List<Airport> results) async =>
      airports[key] = results;
}

/// Trip test helpers.
class InMemoryTripLocalStore implements TripLocalStore {
  InMemoryTripLocalStore({
    List<Trip> trips = const [],
    List<Tag> tags = const [],
  })  : _trips = List.of(trips),
        _tags = List.of(tags);

  List<Trip> _trips;
  List<Tag> _tags;

  @override
  Future<List<Trip>> readTrips() async => List.of(_trips);

  @override
  Future<void> writeTrips(List<Trip> trips) async =>
      _trips = List.of(trips);

  @override
  List<Tag> readTags() => List.of(_tags);

  @override
  Future<List<Tag>> readTagsAsync() async {
    final result = List.of(_tags);
    _tags = List.of(result);
    return result;
  }

  @override
  void addTrip(Trip trip) {
    final existing = _trips
        .where((t) => t.id == trip.id)
        .toList(growable: false);
    _trips.addAll(trips.map((t) => existing.isNotEmpty && t.id == trip.id
        ? existing.first
        : t));
  }
}
