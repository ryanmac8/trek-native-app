import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'packing_item.dart';

/// Persists a trip's packing-list items between app launches, keyed per
/// trip so multiple trips' packing lists can be cached independently — the
/// local cache [PackingRepository] reads from and writes to so the Packing
/// tab never has to block on the network to show items it has already seen
/// (see docs/offline-first.md). Holds a mix of server-confirmed items and
/// any still-[PackingItem.isPending] ones created while offline.
abstract class PackingLocalStore {
  Future<List<PackingItem>> read(String tripId);
  Future<void> write(String tripId, List<PackingItem> items);
}

/// Stores each trip's cached packing item list as JSON in
/// `shared_preferences`. Like [PreferencesBudgetLocalStore], none of this
/// is a secret, so plain (non-secure) storage is fine.
class PreferencesPackingLocalStore implements PackingLocalStore {
  PreferencesPackingLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.packing.cache.$tripId';

  @override
  Future<List<PackingItem>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => PackingItem.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<PackingItem> items) async {
    final encoded = jsonEncode(
      items.map((item) => item.toCacheJson()).toList(),
    );
    await _preferences.setString(_key(tripId), encoded);
  }
}
