import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'budget_item.dart';

/// Persists a trip's budget items between app launches, keyed per trip so
/// multiple trips' budgets can be cached independently — the local cache
/// [BudgetRepository] reads from and writes to so the Budget tab never has
/// to block on the network to show items it has already seen (see
/// docs/offline-first.md). Holds a mix of server-confirmed items and any
/// still-[BudgetItem.isPending] ones created while offline.
abstract class BudgetLocalStore {
  Future<List<BudgetItem>> read(String tripId);
  Future<void> write(String tripId, List<BudgetItem> items);
}

/// Stores each trip's cached budget item list as JSON in
/// `shared_preferences`. Like [PreferencesPlacesLocalStore], none of this
/// is a secret, so plain (non-secure) storage is fine.
class PreferencesBudgetLocalStore implements BudgetLocalStore {
  PreferencesBudgetLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.budget.cache.$tripId';

  @override
  Future<List<BudgetItem>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => BudgetItem.fromCacheJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<BudgetItem> items) async {
    final encoded = jsonEncode(
      items.map((item) => item.toCacheJson()).toList(),
    );
    await _preferences.setString(_key(tripId), encoded);
  }
}
