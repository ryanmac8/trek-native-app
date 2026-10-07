import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'addon_flags.dart';

/// Local cache of the last-fetched [AddonFlags] (see docs/offline-first.md).
///
/// Add-on flags are instance-wide configuration, not per-user data, so
/// entries are keyed by server (its public URL) rather than by account.
/// `null` from [read] means "nothing cached for this server".
abstract class AddonFlagsLocalStore {
  Future<CachedAddonFlags?> read(String server);
  Future<void> write(String server, CachedAddonFlags flags);
}

/// Stores each server's flags as one JSON string in `shared_preferences`.
/// Nothing here is secret, so plain (non-secure) storage is fine.
class PreferencesAddonFlagsLocalStore implements AddonFlagsLocalStore {
  PreferencesAddonFlagsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _key(String server) => 'trek.addons.flags.$server';

  @override
  Future<CachedAddonFlags?> read(String server) async {
    final raw = await _preferences.getString(_key(server));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CachedAddonFlags.fromJson(decoded);
    } on Object {
      // A corrupt or outdated entry is a cache miss, not a crash — the next
      // successful refresh overwrites it.
      return null;
    }
  }

  @override
  Future<void> write(String server, CachedAddonFlags flags) =>
      _preferences.setString(_key(server), jsonEncode(flags.toJson()));
}
