import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'day.dart';

/// Persists a trip's day list between app launches, keyed per trip so
/// multiple trips' itineraries can be cached independently — the local
/// cache [DaysRepository] reads from and writes to so the Days tab never
/// has to block on the network to show days it has already seen (see
/// docs/offline-first.md).
abstract class DaysLocalStore {
  Future<List<Day>> read(String tripId);
  Future<void> write(String tripId, List<Day> days);
}

/// Stores each trip's cached day list as JSON in `shared_preferences`. Like
/// [PreferencesTripsLocalStore], none of this is a secret, so plain
/// (non-secure) storage is fine.
class PreferencesDaysLocalStore implements DaysLocalStore {
  PreferencesDaysLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.days.cache.$tripId';

  @override
  Future<List<Day>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => Day.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<Day> days) async {
    final encoded = jsonEncode(days.map((d) => d.toCacheJson()).toList());
    await _preferences.setString(_key(tripId), encoded);
  }
}
