import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'journey_models.dart';

/// Local cache for the signed-in account's journeys (see
/// docs/offline-first.md): one snapshot of the journey list, and one per
/// opened journey.
///
/// Entries are keyed by an account scope (server + user id — see
/// `journeyCacheScopeProvider`), so switching accounts or servers on the
/// same device never shows another account's journeys. `null` from a read
/// means "nothing cached for this scope".
///
/// Reads are the only operation this slice needs — creating and editing
/// journeys and entries are mutations that need the durable outbox issue
/// #21 will decide on, so there is no outbox here.
abstract class JourneyLocalStore {
  Future<CachedJourney<JourneyList>?> readList(String scope);
  Future<void> writeList(String scope, CachedJourney<JourneyList> list);
  Future<CachedJourney<JourneyDetail>?> readJourney(String scope, int id);
  Future<void> writeJourney(String scope, CachedJourney<JourneyDetail> journey);
}

/// Stores each snapshot as one JSON string in `shared_preferences`. None
/// of it is a credential, so plain (non-secure) storage is fine — the same
/// reasoning as `PreferencesServerConfigStorage`.
class PreferencesJourneyLocalStore implements JourneyLocalStore {
  PreferencesJourneyLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _listKey(String scope) => 'trek.journey.list.$scope';
  static String _journeyKey(String scope, int id) =>
      'trek.journey.detail.$id.$scope';

  @override
  Future<CachedJourney<JourneyList>?> readList(String scope) =>
      _read(_listKey(scope), JourneyList.fromJson);

  @override
  Future<void> writeList(String scope, CachedJourney<JourneyList> list) =>
      _write(_listKey(scope), list.value.toJson(), list.fetchedAt);

  @override
  Future<CachedJourney<JourneyDetail>?> readJourney(String scope, int id) =>
      _read(_journeyKey(scope, id), JourneyDetail.fromJson);

  @override
  Future<void> writeJourney(
    String scope,
    CachedJourney<JourneyDetail> journey,
  ) => _write(
    _journeyKey(scope, journey.value.id),
    journey.value.toJson(),
    journey.fetchedAt,
  );

  Future<CachedJourney<T>?> _read<T>(
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await _preferences.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedJourney(
        value: parse(decoded['value'] as Map<String, dynamic>),
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
      );
    } on Object {
      // A corrupt or outdated entry is treated as a cache miss, not a
      // crash — the next successful refresh overwrites it.
      return null;
    }
  }

  Future<void> _write(
    String key,
    Map<String, dynamic> value,
    DateTime fetchedAt,
  ) => _preferences.setString(
    key,
    jsonEncode({'value': value, 'fetchedAt': fetchedAt.toIso8601String()}),
  );
}
