import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'place.dart';

/// Persists the server's place-category list between app launches, so the
/// place form's category picker works offline (see docs/offline-first.md).
/// Categories are server-wide, not per trip, so there's a single entry.
abstract class CategoriesLocalStore {
  Future<List<PlaceCategoryRef>> read();
  Future<void> write(List<PlaceCategoryRef> categories);
}

/// Stores the category list as JSON in `shared_preferences` under
/// `trek.categories.cache`. Not a secret, so plain storage is fine.
class PreferencesCategoriesLocalStore implements CategoriesLocalStore {
  PreferencesCategoriesLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _key = 'trek.categories.cache';

  @override
  Future<List<PlaceCategoryRef>> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (json) =>
              PlaceCategoryRef.fromCacheJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> write(List<PlaceCategoryRef> categories) async {
    final encoded = jsonEncode(
      categories.map((category) => category.toCacheJson()).toList(),
    );
    await _preferences.setString(_key, encoded);
  }
}
