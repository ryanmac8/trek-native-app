import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'reservation.dart';

/// Persists a trip's reservations between app launches, keyed per trip so
/// multiple trips' bookings can be cached independently — the local cache
/// [ReservationsRepository] reads from and writes to so the Bookings tab
/// never has to block on the network to show reservations it has already
/// seen (see docs/offline-first.md).
abstract class ReservationsLocalStore {
  Future<List<Reservation>> read(String tripId);
  Future<void> write(String tripId, List<Reservation> reservations);
}

/// Stores each trip's cached reservation list as JSON in
/// `shared_preferences`. Like the accommodations cache, none of this is a
/// secret, so plain (non-secure) storage is fine.
class PreferencesReservationsLocalStore implements ReservationsLocalStore {
  PreferencesReservationsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.reservations.cache.$tripId';

  @override
  Future<List<Reservation>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Reservation.fromCacheJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<Reservation> reservations) async {
    final encoded = jsonEncode(
      reservations.map((r) => r.toCacheJson()).toList(),
    );
    await _preferences.setString(_key(tripId), encoded);
  }
}
