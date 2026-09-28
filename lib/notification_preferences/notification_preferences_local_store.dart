import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_preferences_models.dart';

/// Local cache for the signed-in account's notification preferences,
/// including changes not yet confirmed by the server (see
/// docs/offline-first.md).
///
/// Entries are keyed by an account scope (server + user id — see
/// `notificationPreferencesCacheScopeProvider`), so switching accounts or
/// servers on the same device never shows or syncs another account's
/// preferences. `null` from [read] means "nothing cached for this scope".
abstract class NotificationPreferencesLocalStore {
  Future<CachedNotificationPreferences?> read(String scope);
  Future<void> write(String scope, CachedNotificationPreferences value);
}

/// Stores each scope's snapshot as one JSON string in `shared_preferences`.
/// None of it is secret, so plain (non-secure) storage is fine — the same
/// reasoning as `PreferencesServerConfigStorage`.
class PreferencesNotificationPreferencesLocalStore
    implements NotificationPreferencesLocalStore {
  PreferencesNotificationPreferencesLocalStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _key(String scope) => 'trek.notificationPreferences.$scope';

  @override
  Future<CachedNotificationPreferences?> read(String scope) async {
    final raw = await _preferences.getString(_key(scope));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CachedNotificationPreferences.fromJson(decoded);
    } on Object {
      // A corrupt or outdated entry is treated as a cache miss, not a
      // crash — the next successful refresh overwrites it.
      return null;
    }
  }

  @override
  Future<void> write(String scope, CachedNotificationPreferences value) =>
      _preferences.setString(_key(scope), jsonEncode(value.toJson()));
}
