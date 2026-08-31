import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_models.dart';

/// Local cache for the signed-in account (see docs/offline-first.md).
///
/// There is exactly one current account, so this is a single slot rather
/// than a keyed map. `null` from [read] means "nothing cached" (never
/// fetched, or cleared on sign-out).
///
/// Reads are the only operation — editing the profile is a mutation that
/// needs the durable outbox issue #21 will decide on, and is deferred with
/// it. So there is no outbox here.
abstract class AccountLocalStore {
  Future<TrekAccount?> read();
  Future<void> write(TrekAccount account);
  Future<void> clear();
}

/// Stores the account as a single JSON string in `shared_preferences`.
/// None of it is secret (secrets are stripped server-side before it is
/// sent), so plain (non-secure) storage is fine — the same reasoning as
/// `PreferencesServerConfigStorage`.
class PreferencesAccountLocalStore implements AccountLocalStore {
  PreferencesAccountLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _accountKey = 'trek.account.current';

  @override
  Future<TrekAccount?> read() async {
    final raw = await _preferences.getString(_accountKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return TrekAccount.fromJson(decoded);
  }

  @override
  Future<void> write(TrekAccount account) =>
      _preferences.setString(_accountKey, jsonEncode(account.toJson()));

  @override
  Future<void> clear() => _preferences.remove(_accountKey);
}
