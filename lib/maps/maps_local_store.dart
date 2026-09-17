import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'maps_models.dart';

/// A cached [ReverseGeocodeResult] plus whether it is still within its
/// freshness window.
class CachedReverseGeocode {
  const CachedReverseGeocode({required this.result, required this.isFresh});

  final ReverseGeocodeResult result;
  final bool isFresh;
}

/// A cached [ResolvedPlace] plus whether it is still within its freshness
/// window.
class CachedResolvedPlace {
  const CachedResolvedPlace({required this.place, required this.isFresh});

  final ResolvedPlace place;
  final bool isFresh;
}

/// Local cache for maps/geocoding lookups (see docs/offline-first.md).
///
/// Both reverse-geocode and resolve-url answers are effectively static for a
/// given coordinate/URL — an address doesn't move from one lookup to the
/// next — so entries are kept fresh for a long TTL rather than treated like a
/// live "current conditions" cache. There are no local writes beyond caching
/// a fetched answer, so there is no outbox.
///
/// A `null` read means "never looked up". Entries are kept past their TTL for
/// the offline fallback; [CachedReverseGeocode.isFresh] /
/// [CachedResolvedPlace.isFresh] is how a caller tells a still-good entry
/// from a stale one that [MapsRepository] should still show but try to
/// refresh.
abstract class MapsLocalStore {
  Future<CachedReverseGeocode?> readReverseGeocode(String key);
  Future<void> writeReverseGeocode(String key, ReverseGeocodeResult result);

  Future<CachedResolvedPlace?> readResolvedPlace(String key);
  Future<void> writeResolvedPlace(String key, ResolvedPlace place);
}

/// Stores both caches as JSON strings in `shared_preferences`. None of this
/// is secret, so plain (non-secure) storage is fine.
///
/// Each map is capped at [_maxEntries]; the oldest insertion is evicted first
/// (JSON object key order is insertion order), so repeated lookups can't grow
/// the cache without bound.
class PreferencesMapsLocalStore implements MapsLocalStore {
  PreferencesMapsLocalStore({
    SharedPreferencesAsync? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _clock = clock ?? DateTime.now;

  final SharedPreferencesAsync _preferences;
  final DateTime Function() _clock;

  static const _reverseStoreKey = 'trek.maps.reverse_cache';
  static const _resolveStoreKey = 'trek.maps.resolve_cache';
  static const _maxEntries = 100;

  /// A resolved address/URL rarely changes; a week-long TTL just bounds how
  /// long a place that genuinely moved (a relocated business) can stay wrong
  /// once back online, while keeping almost every repeat lookup free.
  static const _ttl = Duration(days: 7);

  @override
  Future<CachedReverseGeocode?> readReverseGeocode(String key) async {
    final entry = await _readEntry(_reverseStoreKey, key);
    if (entry == null) return null;
    final resultJson = entry['result'];
    if (resultJson is! Map) return null;
    return CachedReverseGeocode(
      result: ReverseGeocodeResult.fromJson(
        Map<String, dynamic>.from(resultJson),
      ),
      isFresh: _isFresh(entry),
    );
  }

  @override
  Future<void> writeReverseGeocode(
    String key,
    ReverseGeocodeResult result,
  ) async {
    await _writeEntry(_reverseStoreKey, key, {'result': result.toJson()});
  }

  @override
  Future<CachedResolvedPlace?> readResolvedPlace(String key) async {
    final entry = await _readEntry(_resolveStoreKey, key);
    if (entry == null) return null;
    final placeJson = entry['place'];
    if (placeJson is! Map) return null;
    return CachedResolvedPlace(
      place: ResolvedPlace.fromJson(Map<String, dynamic>.from(placeJson)),
      isFresh: _isFresh(entry),
    );
  }

  @override
  Future<void> writeResolvedPlace(String key, ResolvedPlace place) async {
    await _writeEntry(_resolveStoreKey, key, {'place': place.toJson()});
  }

  bool _isFresh(Map<String, dynamic> entry) {
    final expiresAt = entry['expiresAtMs'];
    return expiresAt is int && _clock().millisecondsSinceEpoch < expiresAt;
  }

  Future<Map<String, dynamic>?> _readEntry(
    String storeKey,
    String entryKey,
  ) async {
    final map = await _readMap(storeKey);
    final entry = map[entryKey];
    return entry is Map ? Map<String, dynamic>.from(entry) : null;
  }

  Future<void> _writeEntry(
    String storeKey,
    String entryKey,
    Map<String, dynamic> value,
  ) async {
    final map = await _readMap(storeKey);
    final expiresAt = _clock().add(_ttl).millisecondsSinceEpoch;
    // Re-insert at the end so this key becomes the most recent.
    map.remove(entryKey);
    map[entryKey] = {...value, 'expiresAtMs': expiresAt};
    while (map.length > _maxEntries) {
      map.remove(map.keys.first);
    }
    await _preferences.setString(storeKey, jsonEncode(map));
  }

  Future<Map<String, dynamic>> _readMap(String storeKey) async {
    final raw = await _preferences.getString(storeKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }
}
