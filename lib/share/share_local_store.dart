import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'share_link.dart';

/// Persists a trip's share-link state between app launches, keyed per trip
/// so multiple trips' sharing settings cache independently — the local
/// cache [ShareRepository] reads from and writes to so the sharing screen
/// never has to block on the network to show settings it has already seen
/// (see docs/offline-first.md). Unlike the other `*LocalStore`s in this app,
/// there's at most one [ShareLink] per trip, so this stores a single
/// nullable value rather than a list.
abstract class ShareLocalStore {
  Future<ShareLink?> read(String tripId);

  /// Writes [link], or clears the cache entirely when `null` (sharing is
  /// off and fully confirmed — nothing left to retry).
  Future<void> write(String tripId, ShareLink? link);
}

/// Stores each trip's cached share-link state as JSON in
/// `shared_preferences`. Like [PreferencesCollabLocalStore], none of this is
/// a secret — the token is meant to be shared — so plain (non-secure)
/// storage is fine.
class PreferencesShareLocalStore implements ShareLocalStore {
  PreferencesShareLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.share.link.cache.$tripId';

  @override
  Future<ShareLink?> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return null;
    return ShareLink.fromCacheJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(String tripId, ShareLink? link) async {
    if (link == null) {
      await _preferences.remove(_key(tripId));
      return;
    }
    await _preferences.setString(_key(tripId), jsonEncode(link.toCacheJson()));
  }
}
