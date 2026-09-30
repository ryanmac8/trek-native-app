import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'widget_trip.dart';

/// Local cache of the trip list the home-screen widget is built from (see
/// docs/offline-first.md), so the widget can be republished — and its
/// countdown kept current — without a network connection.
///
/// Entries are keyed by an account scope (server + user id — see
/// `homeWidgetCacheScopeProvider`), so another account signing in on the
/// same device never publishes the previous account's trips. `null` from
/// [readTrips] means "nothing cached for this scope".
abstract class WidgetTripStore {
  Future<List<WidgetTrip>?> readTrips(String scope);
  Future<void> writeTrips(String scope, List<WidgetTrip> trips);
}

/// Stores the list as one JSON string in `shared_preferences`. None of it
/// is a credential, so plain (non-secure) storage is fine — the same
/// reasoning as `PreferencesServerConfigStorage`.
class PreferencesWidgetTripStore implements WidgetTripStore {
  PreferencesWidgetTripStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _key(String scope) => 'trek.home_widget.trips.$scope';

  @override
  Future<List<WidgetTrip>?> readTrips(String scope) async {
    final raw = await _preferences.getString(_key(scope));
    if (raw == null) return null;
    try {
      return [
        for (final trip in jsonDecode(raw) as List<dynamic>)
          WidgetTrip.fromJson(trip as Map<String, dynamic>),
      ];
    } on Object {
      // A corrupt or outdated entry is treated as a cache miss, not a
      // crash — the next successful refresh overwrites it.
      return null;
    }
  }

  @override
  Future<void> writeTrips(String scope, List<WidgetTrip> trips) =>
      _preferences.setString(
        _key(scope),
        jsonEncode([for (final trip in trips) trip.toJson()]),
      );
}
