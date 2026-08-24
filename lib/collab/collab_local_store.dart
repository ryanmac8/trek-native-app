import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'collab_note.dart';

/// Persists a trip's collab notes between app launches, keyed per trip so
/// multiple trips' notes can be cached independently — the local cache
/// [CollabRepository] reads from and writes to so the Notes tab never has
/// to block on the network to show notes it has already seen (see
/// docs/offline-first.md). Holds a mix of server-confirmed notes and any
/// still-[CollabNote.isPending] ones created while offline.
abstract class CollabLocalStore {
  Future<List<CollabNote>> read(String tripId);
  Future<void> write(String tripId, List<CollabNote> notes);
}

/// Stores each trip's cached note list as JSON in `shared_preferences`.
/// Like [PreferencesTodoLocalStore], none of this is a secret, so plain
/// (non-secure) storage is fine.
class PreferencesCollabLocalStore implements CollabLocalStore {
  PreferencesCollabLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.collab.notes.cache.$tripId';

  @override
  Future<List<CollabNote>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => CollabNote.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<CollabNote> notes) async {
    final encoded = jsonEncode(
      notes.map((note) => note.toCacheJson()).toList(),
    );
    await _preferences.setString(_key(tripId), encoded);
  }
}
