import '../network/api_exception.dart';
import 'weather_api.dart';
import 'weather_local_store.dart';
import 'weather_models.dart';

/// One weather answer and where it came from.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.report,
    required this.fromCache,
    required this.stale,
  });

  final WeatherReport report;

  /// Served from the local store rather than a fresh fetch.
  final bool fromCache;

  /// Served from the local store *past its TTL* — i.e. a refresh was wanted
  /// but the network failed. The screen shows an offline notice for these.
  final bool stale;
}

/// One day of a [TripForecast].
class ForecastDay {
  const ForecastDay({required this.date, this.weather});

  final DateTime date;

  /// Null when that day had no fresh data and nothing cached to fall back on
  /// (offline, first run) — the row renders as "unavailable" rather than
  /// failing the whole forecast.
  final WeatherSnapshot? weather;
}

/// A short run of days for one destination.
class TripForecast {
  const TripForecast(this.days);

  final List<ForecastDay> days;

  /// True when at least one day is missing or was served stale — the screen
  /// surfaces this as an explicit offline state.
  bool get isPartial => days.any((d) => d.weather == null || d.weather!.stale);
}

/// Offline-first front door for weather (see docs/offline-first.md). Screens
/// use this, not [WeatherApi] directly.
///
/// - [cachedReport] reads the local store only, so a screen can paint the last
///   answer for a coordinate/date instantly.
/// - [report] returns a fresh cache hit as-is; otherwise it fetches, writes the
///   cache, and returns. On a [NetworkException] it falls back to a stale
///   cached answer (flagged [WeatherSnapshot.stale]); only when nothing is
///   cached does the exception propagate, so the caller can show an explicit
///   offline state.
/// - [forecast] runs [report] over a span of days through a small concurrency
///   limit. Each day degrades independently: an offline day with no cache
///   becomes a null [ForecastDay.weather] instead of failing the batch.
class WeatherRepository {
  WeatherRepository({
    required WeatherApi weatherApi,
    required WeatherLocalStore localStore,
  }) : _api = weatherApi,
       _localStore = localStore;

  final WeatherApi _api;
  final WeatherLocalStore _localStore;

  /// Open-Meteo answers a real forecast for roughly the next 16 days; past
  /// that the server switches to a historical-average estimate. The screen
  /// caps its forecast span here so every day still comes back as a forecast.
  static const maxForecastDays = 14;

  /// Trek's web client serialises its per-day weather calls three at a time
  /// (`client/src/services/weatherQueue.ts`); mirror that so a multi-day
  /// forecast doesn't open a dozen sockets at once.
  static const _maxConcurrent = 3;

  static String cacheKeyFor(GeoPoint point, {String? date}) =>
      '${point.cacheKey}_${date ?? 'current'}';

  Future<WeatherReport?> cachedReport(GeoPoint point, {String? date}) async {
    final cached = await _localStore.read(cacheKeyFor(point, date: date));
    return cached?.report;
  }

  Future<WeatherSnapshot> report(
    GeoPoint point, {
    String? date,
    bool forceRefresh = false,
  }) async {
    final key = cacheKeyFor(point, date: date);
    final cached = await _localStore.read(key);

    if (!forceRefresh && cached != null && cached.isFresh) {
      return WeatherSnapshot(
        report: cached.report,
        fromCache: true,
        stale: false,
      );
    }

    try {
      final fresh = await _api.fetch(point, date: date);
      await _localStore.write(key, fresh);
      return WeatherSnapshot(report: fresh, fromCache: false, stale: false);
    } on NetworkException {
      if (cached != null) {
        return WeatherSnapshot(
          report: cached.report,
          fromCache: true,
          stale: true,
        );
      }
      rethrow;
    }
  }

  /// [days] is clamped to `1..maxForecastDays`. [start] is date-only; the time
  /// component is ignored.
  Future<TripForecast> forecast(
    GeoPoint point, {
    required DateTime start,
    int days = 7,
    bool forceRefresh = false,
  }) async {
    final span = days.clamp(1, maxForecastDays);
    final startDate = DateTime.utc(start.year, start.month, start.day);
    final dates = [
      for (var i = 0; i < span; i++) startDate.add(Duration(days: i)),
    ];

    final results = List<ForecastDay?>.filled(dates.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= dates.length) return;
        final date = dates[index];
        try {
          final snapshot = await report(
            point,
            date: _isoDate(date),
            forceRefresh: forceRefresh,
          );
          results[index] = ForecastDay(date: date, weather: snapshot);
        } on NetworkException {
          results[index] = ForecastDay(date: date);
        }
      }
    }

    await Future.wait([for (var i = 0; i < _maxConcurrent; i++) worker()]);

    return TripForecast(results.map((d) => d!).toList(growable: false));
  }

  static String _isoDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
}
