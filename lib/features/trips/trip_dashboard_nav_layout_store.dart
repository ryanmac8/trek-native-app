import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists which tab keys occupy the trip dashboard's 4 visible bottom-nav
/// slots (a `null` entry is an empty slot) — see `TripDashboardScreen`'s
/// drag-and-drop customization.
///
/// This is a device-local UI preference, not trip data: it's the same for
/// every trip and every screen visit, not something read from or written
/// to Trek's backend. Unlike [TripsLocalStore]/[DaysLocalStore] it isn't
/// part of the offline-first trip-data story in docs/offline-first.md —
/// there's nothing to sync or degrade gracefully from, so a plain
/// `shared_preferences` read/write is the whole implementation.
abstract class TripDashboardNavLayoutStore {
  /// Returns `null` when nothing has been customized yet, so the caller can
  /// fall back to its own default layout instead of an empty one.
  Future<List<String?>?> read();
  Future<void> write(List<String?> slotKeys);
}

class PreferencesTripDashboardNavLayoutStore
    implements TripDashboardNavLayoutStore {
  PreferencesTripDashboardNavLayoutStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'trek.trip_dashboard.nav_layout';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String?>?> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => e as String?).toList();
  }

  @override
  Future<void> write(List<String?> slotKeys) async {
    await _preferences.setString(_key, jsonEncode(slotKeys));
  }
}
