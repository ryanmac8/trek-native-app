import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_place_op.dart';
import 'place.dart';

/// Persists a trip's place pool between app launches, keyed per trip so
/// multiple trips' place pools can be cached independently — the local
/// cache [PlacesRepository] reads from and writes to so the Places tab
/// never has to block on the network to show places it has already seen
/// (see docs/offline-first.md).
///
/// Alongside the place list it keeps each trip's outbox of place mutations
/// not yet accepted by the server ([PendingPlaceOp]s, oldest first).
abstract class PlacesLocalStore {
  Future<List<Place>> read(String tripId);
  Future<void> write(String tripId, List<Place> places);
  Future<List<PendingPlaceOp>> readPending(String tripId);
  Future<void> writePending(String tripId, List<PendingPlaceOp> ops);
}

/// Stores each trip's cached place list as JSON in `shared_preferences`.
/// Like [PreferencesDaysLocalStore], none of this is a secret, so plain
/// (non-secure) storage is fine.
class PreferencesPlacesLocalStore implements PlacesLocalStore {
  PreferencesPlacesLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.places.cache.$tripId';
  String _pendingKey(String tripId) => 'trek.places.pending.$tripId';

  @override
  Future<List<Place>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => Place.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<Place> places) async {
    final encoded = jsonEncode(places.map((p) => p.toCacheJson()).toList());
    await _preferences.setString(_key(tripId), encoded);
  }

  @override
  Future<List<PendingPlaceOp>> readPending(String tripId) async {
    final raw = await _preferences.getString(_pendingKey(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => PendingPlaceOp.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> writePending(String tripId, List<PendingPlaceOp> ops) async {
    if (ops.isEmpty) {
      await _preferences.remove(_pendingKey(tripId));
      return;
    }
    final encoded = jsonEncode(ops.map((op) => op.toJson()).toList());
    await _preferences.setString(_pendingKey(tripId), encoded);
  }
}
