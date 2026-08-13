import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'tag.dart';

/// Persists the user's tag list between app launches — the local cache
/// [TagsRepository] reads from and writes to so the UI never has to block
/// on the network to show tags it has already seen (see
/// docs/offline-first.md). Holds a mix of server-confirmed tags and any
/// still-[Tag.isPending] ones created while offline. Unlike
/// [PreferencesPlacesLocalStore], not keyed per trip — tags belong to the
/// user, not a trip.
abstract class TagsLocalStore {
  Future<List<Tag>> read();
  Future<void> write(List<Tag> tags);
}

/// Stores the cached tag list as JSON in `shared_preferences`. Like
/// [PreferencesTripsLocalStore], none of this is a secret, so plain
/// (non-secure) storage is fine.
class PreferencesTagsLocalStore implements TagsLocalStore {
  PreferencesTagsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _tagsKey = 'trek.tags.cache';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<Tag>> read() async {
    final raw = await _preferences.getString(_tagsKey);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => Tag.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(List<Tag> tags) async {
    final encoded = jsonEncode(tags.map((t) => t.toCacheJson()).toList());
    await _preferences.setString(_tagsKey, encoded);
  }
}
