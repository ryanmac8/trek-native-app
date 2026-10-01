import '../network/api_exception.dart';
import 'calendar_feed.dart';
import 'calendar_feed_api.dart';
import 'calendar_feed_store.dart';

enum CalendarFeedSyncStatus {
  /// The snapshot matches the server.
  synced,

  /// The server couldn't be reached (or failed transiently); the snapshot is
  /// the cached one and any pending action is still queued.
  offline,

  /// The account isn't allowed to manage this feed (Trek's `share_manage`
  /// permission). Any pending action was dropped.
  forbidden,

  /// The server rejected the request for good (e.g. the trip no longer
  /// exists). Any pending action was dropped.
  failed,

  /// There's no signed-in account to scope the cache to.
  signedOut,
}

class CalendarFeedSyncResult {
  const CalendarFeedSyncResult(this.snapshot, this.status, [this.message]);

  final CalendarFeedSnapshot snapshot;
  final CalendarFeedSyncStatus status;
  final String? message;
}

/// Offline-first access to a calendar feed's subscription URL.
///
/// [readCached] never touches the network. [request] records the action in
/// the local cache *before* trying the server, so it survives the app being
/// killed while offline; [refresh] retries any pending action and then
/// re-reads the server state. Calls are serialized, so a pending action is
/// never sent twice concurrently.
class CalendarFeedRepository {
  CalendarFeedRepository({
    required CalendarFeedApi api,
    required CalendarFeedStore store,
    required Future<String?> Function() account,
    DateTime Function()? clock,
  }) : _api = api,
       _store = store,
       _account = account,
       _clock = clock ?? DateTime.now;

  final CalendarFeedApi _api;
  final CalendarFeedStore _store;
  final Future<String?> Function() _account;
  final DateTime Function() _clock;

  // Created lazily, so no Future exists before the first call.
  Future<void>? _tail;

  Future<T> _serialized<T>(Future<T> Function() body) {
    final previous = _tail;
    final result = previous == null ? body() : previous.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<CalendarFeedSnapshot?> readCached(CalendarFeedScope scope) async {
    final account = await _account();
    if (account == null) return null;
    return _store.read(account, scope);
  }

  /// Sends any pending action, then fetches the current feed URL.
  Future<CalendarFeedSyncResult> refresh(CalendarFeedScope scope) =>
      _serialized(() => _sync(scope, fetchAfter: true));

  /// Applies [action] locally, then tries to send it.
  Future<CalendarFeedSyncResult> request(
    CalendarFeedScope scope,
    CalendarFeedAction action,
  ) => _serialized(() async {
    final account = await _account();
    if (account == null) {
      return const CalendarFeedSyncResult(
        CalendarFeedSnapshot.empty,
        CalendarFeedSyncStatus.signedOut,
      );
    }
    final current =
        await _store.read(account, scope) ?? CalendarFeedSnapshot.empty;
    await _store.write(account, scope, current.withPending(action));
    return _sync(scope, fetchAfter: false);
  });

  Future<CalendarFeedSyncResult> _sync(
    CalendarFeedScope scope, {
    required bool fetchAfter,
  }) async {
    final account = await _account();
    if (account == null) {
      return const CalendarFeedSyncResult(
        CalendarFeedSnapshot.empty,
        CalendarFeedSyncStatus.signedOut,
      );
    }
    final cached =
        await _store.read(account, scope) ?? CalendarFeedSnapshot.empty;
    try {
      final pending = cached.pending;
      final String? url;
      if (pending != null) {
        url = await _api.apply(scope, pending);
      } else if (fetchAfter) {
        url = await _api.fetch(scope);
      } else {
        return CalendarFeedSyncResult(cached, CalendarFeedSyncStatus.synced);
      }
      final synced = CalendarFeedSnapshot(feedUrl: url, syncedAt: _clock());
      await _store.write(account, scope, synced);
      return CalendarFeedSyncResult(synced, CalendarFeedSyncStatus.synced);
    } on ApiException catch (e) {
      if (_isRetryable(e)) {
        return CalendarFeedSyncResult(
          cached,
          CalendarFeedSyncStatus.offline,
          e.message,
        );
      }
      // Permanent rejection: the cached URL can't be trusted either (the
      // trip may be gone, or the account lost the permission to see it).
      await _store.write(account, scope, CalendarFeedSnapshot.empty);
      return CalendarFeedSyncResult(
        CalendarFeedSnapshot.empty,
        e is ForbiddenException
            ? CalendarFeedSyncStatus.forbidden
            : CalendarFeedSyncStatus.failed,
        e.message,
      );
    }
  }

  static bool _isRetryable(ApiException e) => switch (e) {
    NetworkException() || UnauthorizedException() => true,
    ServerException(:final statusCode) => statusCode >= 500,
    ForbiddenException() || ValidationException() => false,
  };
}
