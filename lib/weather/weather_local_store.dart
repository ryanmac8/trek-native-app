import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'weather_models.dart';

/// A cached [WeatherReport] plus whether it is still within its
/// kind-dependent freshness window.
class CachedWeather {
  const CachedWeather({required this.report, required this.isFresh});

  final WeatherReport report;

  /// False once the entry is past its TTL. A stale entry is still returned —
  /// [WeatherRepository] paints it immediately and uses it as the offline
  /// fallback — but a stale entry does not stop a background refresh.
  final bool isFresh;
}

/// Local cache for weather lookups (see docs/offline-first.md).
///
/// Weather is an online read — there is no bundled model — but the last answer
/// for a coordinate/date is kept so a repeated lookup paints instantly and
/// still shows *something* when the network is down. There are no local writes,
/// so this has no outbox.
///
/// A `null` read means "never fetched". Entries are kept past their TTL for the
/// offline fallback; [CachedWeather.isFresh] is how a caller tells a
/// still-good entry from a stale one.
abstract class WeatherLocalStore {
  Future<CachedWeather?> read(String key);
  Future<void> write(String key, WeatherReport report);
}

/// Stores the whole cache as one JSON string in `shared_preferences`. None of
/// this is secret, so plain (non-secure) storage is fine.
///
/// The map is capped at [_maxEntries]; the oldest insertion is evicted first
/// (JSON object key order is insertion order), so a session of lookups can't
/// grow the cache without bound.
class PreferencesWeatherLocalStore implements WeatherLocalStore {
  PreferencesWeatherLocalStore({
    SharedPreferencesAsync? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _clock = clock ?? DateTime.now;

  final SharedPreferencesAsync _preferences;
  final DateTime Function() _clock;

  static const _storeKey = 'trek.weather.cache';
  static const _maxEntries = 60;

  /// Freshness windows, mirroring the server-side TTLs in `weather.impl.ts`
  /// (`TTL_CURRENT_MS` / `TTL_FORECAST_MS` / `TTL_CLIMATE_MS`). A `no_forecast`
  /// answer is kept only briefly so a transient provider gap self-heals.
  static Duration ttlFor(WeatherKind kind) {
    switch (kind) {
      case WeatherKind.current:
        return const Duration(minutes: 15);
      case WeatherKind.forecast:
        return const Duration(hours: 1);
      case WeatherKind.climate:
        return const Duration(hours: 24);
      case WeatherKind.unknown:
        return const Duration(minutes: 10);
    }
  }

  @override
  Future<CachedWeather?> read(String key) async {
    final map = await _readMap();
    final entry = map[key];
    if (entry is! Map) return null;
    final reportJson = entry['report'];
    if (reportJson is! Map) return null;
    final report = WeatherReport.fromJson(
      Map<String, dynamic>.from(reportJson),
    );
    final expiresAt = entry['expiresAtMs'];
    final isFresh =
        expiresAt is int && _clock().millisecondsSinceEpoch < expiresAt;
    return CachedWeather(report: report, isFresh: isFresh);
  }

  @override
  Future<void> write(String key, WeatherReport report) async {
    final map = await _readMap();
    final expiresAt = _clock().add(ttlFor(report.kind)).millisecondsSinceEpoch;
    // Re-insert at the end so this key becomes the most recent.
    map.remove(key);
    map[key] = {'report': report.toJson(), 'expiresAtMs': expiresAt};
    while (map.length > _maxEntries) {
      map.remove(map.keys.first);
    }
    await _preferences.setString(_storeKey, jsonEncode(map));
  }

  Future<Map<String, dynamic>> _readMap() async {
    final raw = await _preferences.getString(_storeKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }
}
