import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'vacay_models.dart';

/// Local cache for the signed-in account's Vacay plan and per-year data
/// (see docs/offline-first.md).
///
/// Entries are keyed by an account scope (server + user id — see
/// `vacayCacheScopeProvider`), so switching accounts or servers on the same
/// device never shows another account's plan. `null` from a read means
/// "nothing cached for this scope".
///
/// Reads are the only operation this slice needs — toggling days and
/// editing plan settings are mutations that need the durable outbox
/// issue #21 will decide on, so there is no outbox here.
abstract class VacayLocalStore {
  Future<CachedVacay<VacayPlan>?> readPlan(String scope);
  Future<void> writePlan(String scope, CachedVacay<VacayPlan> plan);
  Future<CachedVacay<VacayYear>?> readYear(String scope, int year);
  Future<void> writeYear(String scope, CachedVacay<VacayYear> year);
}

/// Stores each snapshot as one JSON string in `shared_preferences`: one
/// for the plan, one per year. None of it is secret (members' email
/// addresses are dropped before caching), so plain (non-secure) storage is
/// fine — the same reasoning as `PreferencesServerConfigStorage`.
class PreferencesVacayLocalStore implements VacayLocalStore {
  PreferencesVacayLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _planKey(String scope) => 'trek.vacay.plan.$scope';
  static String _yearKey(String scope, int year) =>
      'trek.vacay.year.$year.$scope';

  @override
  Future<CachedVacay<VacayPlan>?> readPlan(String scope) =>
      _read(_planKey(scope), VacayPlan.fromCacheJson);

  @override
  Future<void> writePlan(String scope, CachedVacay<VacayPlan> plan) =>
      _write(_planKey(scope), plan.value.toJson(), plan.fetchedAt);

  @override
  Future<CachedVacay<VacayYear>?> readYear(String scope, int year) =>
      _read(_yearKey(scope, year), VacayYear.fromCacheJson);

  @override
  Future<void> writeYear(String scope, CachedVacay<VacayYear> year) => _write(
    _yearKey(scope, year.value.year),
    year.value.toJson(),
    year.fetchedAt,
  );

  Future<CachedVacay<T>?> _read<T>(
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await _preferences.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedVacay(
        value: parse(decoded['value'] as Map<String, dynamic>),
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
      );
    } on Object {
      // A corrupt or outdated entry is treated as a cache miss, not a
      // crash — the next successful refresh overwrites it.
      return null;
    }
  }

  Future<void> _write(
    String key,
    Map<String, dynamic> value,
    DateTime fetchedAt,
  ) => _preferences.setString(
    key,
    jsonEncode({'value': value, 'fetchedAt': fetchedAt.toIso8601String()}),
  );
}
