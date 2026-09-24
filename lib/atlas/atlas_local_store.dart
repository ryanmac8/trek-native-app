import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'atlas_models.dart';

/// Local cache for the signed-in account's Atlas stats (see
/// docs/offline-first.md).
///
/// Entries are keyed by an account scope (server + user id — see
/// `atlasCacheScopeProvider`), so switching accounts or servers on the same
/// device never shows another account's stats. `null` from [read] means
/// "nothing cached for this scope".
///
/// Reads are the only operation this slice needs — marking countries and
/// editing the bucket list are mutations that need the durable outbox
/// issue #21 will decide on, so there is no outbox here.
abstract class AtlasLocalStore {
  Future<CachedAtlasStats?> read(String scope);
  Future<void> write(String scope, CachedAtlasStats stats);
}

/// Stores each scope's snapshot as one JSON string in `shared_preferences`.
/// None of it is secret, so plain (non-secure) storage is fine — the same
/// reasoning as `PreferencesServerConfigStorage`.
class PreferencesAtlasLocalStore implements AtlasLocalStore {
  PreferencesAtlasLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _key(String scope) => 'trek.atlas.stats.$scope';

  @override
  Future<CachedAtlasStats?> read(String scope) async {
    final raw = await _preferences.getString(_key(scope));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CachedAtlasStats.fromJson(decoded);
    } on Object {
      // A corrupt or outdated entry is treated as a cache miss, not a
      // crash — the next successful refresh overwrites it.
      return null;
    }
  }

  @override
  Future<void> write(String scope, CachedAtlasStats stats) =>
      _preferences.setString(_key(scope), jsonEncode(stats.toJson()));
}
