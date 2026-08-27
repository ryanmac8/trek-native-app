import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'accommodation.dart';

/// Persists a trip's accommodations between app launches, keyed per trip so
/// multiple trips' stays can be cached independently — the local cache
/// [AccommodationsRepository] reads from and writes to so the Stays tab
/// never has to block on the network to show accommodations it has already
/// seen (see docs/offline-first.md).
abstract class AccommodationsLocalStore {
  Future<List<Accommodation>> read(String tripId);
  Future<void> write(String tripId, List<Accommodation> accommodations);
}

/// Stores each trip's cached accommodation list as JSON in
/// `shared_preferences`. Like the places cache, none of this is a secret,
/// so plain (non-secure) storage is fine.
class PreferencesAccommodationsLocalStore implements AccommodationsLocalStore {
  PreferencesAccommodationsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.accommodations.cache.$tripId';

  @override
  Future<List<Accommodation>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Accommodation.fromCacheJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<Accommodation> accommodations) async {
    final encoded = jsonEncode(
      accommodations.map((a) => a.toCacheJson()).toList(),
    );
    await _preferences.setString(_key(tripId), encoded);
  }
}
