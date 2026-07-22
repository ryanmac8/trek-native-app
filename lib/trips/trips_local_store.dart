import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trip.dart';

/// Persists the trip list between app launches — the local cache
/// [TripsRepository] reads from and writes to so the UI never has to block
/// on the network to show trips it has already seen (see
/// docs/offline-first.md). Holds a mix of server-confirmed trips and any
/// still-[Trip.isPending] ones created while offline.
abstract class TripsLocalStore {
  Future<List<Trip>> read();
  Future<void> write(List<Trip> trips);

  /// Ids of trips deleted locally ([TripsRepository.deleteTrip]) whose
  /// `DELETE` call hasn't reached the server yet — retried by the next
  /// [TripsRepository.refreshTrips] call. Tracked separately from the trip
  /// list itself since a deleted trip is removed from that list immediately.
  Future<Set<int>> readPendingDeletes();
  Future<void> writePendingDeletes(Set<int> ids);
}

/// Stores the cached trip list as JSON in `shared_preferences`. Like
/// [PreferencesServerConfigStorage], none of this is a secret, so plain
/// (non-secure) storage is fine.
class PreferencesTripsLocalStore implements TripsLocalStore {
  PreferencesTripsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _tripsKey = 'trek.trips.cache';
  static const _pendingDeletesKey = 'trek.trips.pending_deletes';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<Trip>> read() async {
    final raw = await _preferences.getString(_tripsKey);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => Trip.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(List<Trip> trips) async {
    final encoded = jsonEncode(trips.map((t) => t.toCacheJson()).toList());
    await _preferences.setString(_tripsKey, encoded);
  }

  @override
  Future<Set<int>> readPendingDeletes() async {
    final raw = await _preferences.getString(_pendingDeletesKey);
    if (raw == null) return const {};
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<int>().toSet();
  }

  @override
  Future<void> writePendingDeletes(Set<int> ids) async {
    await _preferences.setString(_pendingDeletesKey, jsonEncode(ids.toList()));
  }
}
