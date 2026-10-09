import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cache_entry.dart';

/// Durable key → [CacheEntry] storage behind [ReadCache].
///
/// Keys are opaque to the store; [ReadCache] builds them from the account
/// scope and the resource key.
abstract class CacheStore {
  /// `null` for a missing or unreadable entry.
  Future<CacheEntry?> read(String key);
  Future<void> write(String key, CacheEntry entry);
  Future<void> remove(String key);

  /// Every key currently stored.
  Future<Set<String>> keys();
}

/// Stores each entry as one JSON string in `shared_preferences`, under
/// `trek.cache.<key>`. Cached trip data isn't secret (the session token
/// lives in secure storage), so plain storage is fine.
class PreferencesCacheStore implements CacheStore {
  PreferencesCacheStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const prefix = 'trek.cache.';

  @override
  Future<CacheEntry?> read(String key) async {
    final raw = await _preferences.getString('$prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CacheEntry.fromJson(decoded);
    } on FormatException {
      // A corrupt entry is a cache miss; the next refresh overwrites it.
      return null;
    }
  }

  @override
  Future<void> write(String key, CacheEntry entry) =>
      _preferences.setString('$prefix$key', jsonEncode(entry.toJson()));

  @override
  Future<void> remove(String key) => _preferences.remove('$prefix$key');

  @override
  Future<Set<String>> keys() async {
    final all = await _preferences.getKeys();
    return {
      for (final key in all)
        if (key.startsWith(prefix)) key.substring(prefix.length),
    };
  }
}
