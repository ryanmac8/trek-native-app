import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'transit_models.dart';

/// Local cache for transit + airport search (see docs/offline-first.md).
///
/// Search and route planning are inherently online operations — there is no
/// bundled transit graph — but the last results for a query are kept so a
/// repeated search paints instantly and still shows *something* useful when
/// the network is down. There are no local writes here (creating an
/// itinerary entry from a result needs the Days feature, issue #4), so this
/// has no outbox.
///
/// Each of the three result kinds is a small bounded map keyed by a
/// normalised query string; `null` from a read means "never fetched"
/// (distinct from an empty list, which means "fetched, no matches").
abstract class TransitLocalStore {
  Future<List<TransitPlace>?> readStopSearch(String key);
  Future<void> writeStopSearch(String key, List<TransitPlace> results);

  Future<List<TransitItinerary>?> readRoutePlan(String key);
  Future<void> writeRoutePlan(String key, List<TransitItinerary> itineraries);

  Future<List<Airport>?> readAirportSearch(String key);
  Future<void> writeAirportSearch(String key, List<Airport> results);
}

/// Stores each result map as a single JSON string in `shared_preferences`.
/// None of this is secret, so plain (non-secure) storage is fine.
///
/// Each map is capped at [_maxEntries]; the oldest insertion is evicted
/// first (JSON object key order is insertion order), so a session of
/// typeahead searches can't grow the cache without bound.
class PreferencesTransitLocalStore implements TransitLocalStore {
  PreferencesTransitLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _stopSearchKey = 'trek.transit.stop_search';
  static const _routePlanKey = 'trek.transit.route_plans';
  static const _airportSearchKey = 'trek.transit.airport_search';
  static const _maxEntries = 30;

  @override
  Future<List<TransitPlace>?> readStopSearch(String key) =>
      _readEntry(_stopSearchKey, key, TransitPlace.fromJson);

  @override
  Future<void> writeStopSearch(String key, List<TransitPlace> results) =>
      _writeEntry(_stopSearchKey, key, results.map((e) => e.toJson()).toList());

  @override
  Future<List<TransitItinerary>?> readRoutePlan(String key) =>
      _readEntry(_routePlanKey, key, TransitItinerary.fromJson);

  @override
  Future<void> writeRoutePlan(String key, List<TransitItinerary> itineraries) =>
      _writeEntry(
        _routePlanKey,
        key,
        itineraries.map((e) => e.toJson()).toList(),
      );

  @override
  Future<List<Airport>?> readAirportSearch(String key) =>
      _readEntry(_airportSearchKey, key, Airport.fromJson);

  @override
  Future<void> writeAirportSearch(String key, List<Airport> results) =>
      _writeEntry(
        _airportSearchKey,
        key,
        results.map((e) => e.toJson()).toList(),
      );

  Future<Map<String, dynamic>> _readMap(String storeKey) async {
    final raw = await _preferences.getString(storeKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<List<T>?> _readEntry<T>(
    String storeKey,
    String entryKey,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final map = await _readMap(storeKey);
    final entry = map[entryKey];
    if (entry is! List) return null;
    return entry
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> _writeEntry(
    String storeKey,
    String entryKey,
    List<Map<String, dynamic>> value,
  ) async {
    final map = await _readMap(storeKey);
    // Re-insert at the end so this key becomes the most recent.
    map.remove(entryKey);
    map[entryKey] = value;
    while (map.length > _maxEntries) {
      map.remove(map.keys.first);
    }
    await _preferences.setString(storeKey, jsonEncode(map));
  }
}
