import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'todo_item.dart';

/// Persists a trip's todo-list items between app launches, keyed per trip so
/// multiple trips' todo lists can be cached independently — the local cache
/// [TodoRepository] reads from and writes to so the Todos tab never has to
/// block on the network to show items it has already seen (see
/// docs/offline-first.md). Holds a mix of server-confirmed items and any
/// still-[TodoItem.isPending] ones created while offline.
abstract class TodoLocalStore {
  Future<List<TodoItem>> read(String tripId);
  Future<void> write(String tripId, List<TodoItem> items);
}

/// Stores each trip's cached todo item list as JSON in
/// `shared_preferences`. Like [PreferencesPackingLocalStore], none of this
/// is a secret, so plain (non-secure) storage is fine.
class PreferencesTodoLocalStore implements TodoLocalStore {
  PreferencesTodoLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.todo.cache.$tripId';

  @override
  Future<List<TodoItem>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => TodoItem.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<TodoItem> items) async {
    final encoded = jsonEncode(
      items.map((item) => item.toCacheJson()).toList(),
    );
    await _preferences.setString(_key(tripId), encoded);
  }
}
