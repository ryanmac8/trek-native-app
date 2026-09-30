import 'package:flutter/foundation.dart';

import '../network/api_exception.dart';
import 'home_widget_publisher.dart';
import 'widget_trip.dart';
import 'widget_trip_api.dart';
import 'widget_trip_store.dart';

/// What a [NextTripWidgetSync.refresh] ended up publishing.
enum NextTripWidgetSyncResult {
  /// Fresh trips from the server were cached and published.
  fresh,

  /// The server couldn't be reached (or failed); the cached trips were
  /// republished against today's date.
  cached,

  /// The server couldn't be reached and nothing was cached; the widget
  /// was left as it was.
  unavailable,

  /// There's no live session; the widget was cleared.
  signedOut,
}

/// Keeps the "Next trip" home-screen widget's data current, offline-first
/// (see docs/offline-first.md and docs/home-widgets.md):
///
/// 1. With no session ([cacheScope] returns `null`), the widget is cleared.
/// 2. Otherwise the cached trip list is republished straight away — no
///    network needed — so the countdown reflects today's date even offline.
/// 3. Then `GET /api/trips` is fetched; on success the list is cached and
///    published again. A `NetworkException` or server error leaves the
///    cached publish in place. An `UnauthorizedException` means the session
///    is gone (the shared client has already cleared it), so the widget is
///    cleared.
///
/// Concurrent calls share one in-flight refresh.
class NextTripWidgetSync {
  NextTripWidgetSync({
    required WidgetTripApi api,
    required WidgetTripStore store,
    required HomeWidgetPublisher publisher,
    required Future<String?> Function() cacheScope,
    DateTime Function()? clock,
  }) : _api = api,
       _store = store,
       _publisher = publisher,
       _cacheScope = cacheScope,
       _clock = clock ?? DateTime.now;

  final WidgetTripApi _api;
  final WidgetTripStore _store;
  final HomeWidgetPublisher _publisher;
  final Future<String?> Function() _cacheScope;
  final DateTime Function() _clock;

  Future<NextTripWidgetSyncResult>? _inFlight;

  Future<NextTripWidgetSyncResult> refresh() {
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  /// Clears the widget, e.g. on sign-out. The cached trip list stays, so
  /// signing back into the same account republishes it offline.
  Future<void> clear() => _publisher.clear();

  Future<NextTripWidgetSyncResult> _refresh() async {
    final scope = await _cacheScope();
    if (scope == null) {
      await _publisher.clear();
      return NextTripWidgetSyncResult.signedOut;
    }

    final cached = await _store.readTrips(scope);
    if (cached != null) await _publish(cached);

    final List<WidgetTrip> trips;
    try {
      trips = await _api.fetchTrips();
    } on UnauthorizedException {
      await _publisher.clear();
      return NextTripWidgetSyncResult.signedOut;
    } on ApiException catch (error) {
      debugPrint('NextTripWidgetSync: refresh failed: $error');
      return cached != null
          ? NextTripWidgetSyncResult.cached
          : NextTripWidgetSyncResult.unavailable;
    }

    await _store.writeTrips(scope, trips);
    await _publish(trips);
    return NextTripWidgetSyncResult.fresh;
  }

  Future<void> _publish(List<WidgetTrip> trips) =>
      _publisher.publishNextTrip(nextTripCandidates(trips, _clock()));
}
