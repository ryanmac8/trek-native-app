import '../network/api_exception.dart';
import 'notification_preferences_api.dart';
import 'notification_preferences_local_store.dart';
import 'notification_preferences_models.dart';

/// Offline-first front door for notification preferences (see
/// docs/offline-first.md). The preferences screen uses this, not
/// [NotificationPreferencesApi] directly.
///
/// - [cached] never touches the network, so the screen can paint the
///   last-known matrix (with unsynced local changes applied) instantly.
/// - [setPreference] applies a toggle to the local cache only and records
///   it as pending; it never touches the network and never fails for lack
///   of a connection.
/// - [syncPending] pushes pending cells to the server. A
///   `NetworkException` propagates and the cells stay pending for the next
///   attempt. A rejection (any other `ApiException` except a 401) drops the
///   rejected cells, so the server's value shows again, and propagates.
/// - [refresh] syncs pending cells first, then fetches the server matrix.
///
/// Everything is scoped to the current account via [cacheScope]; with no
/// scope (no live session) nothing is read from or written to the cache.
/// An `UnauthorizedException` always propagates with the pending cells
/// kept: the shared client has already cleared the session, and the router
/// redirects to login.
class NotificationPreferencesRepository {
  NotificationPreferencesRepository({
    required NotificationPreferencesApi api,
    required NotificationPreferencesLocalStore localStore,
    required Future<String?> Function() cacheScope,
    DateTime Function()? clock,
  }) : _api = api,
       _localStore = localStore,
       _cacheScope = cacheScope,
       _clock = clock ?? DateTime.now;

  final NotificationPreferencesApi _api;
  final NotificationPreferencesLocalStore _localStore;
  final Future<String?> Function() _cacheScope;
  final DateTime Function() _clock;

  /// Serializes read-modify-write cycles on the local store so a toggle
  /// made while a sync is in flight is never lost.
  Future<void> _storeLock = Future.value();

  Future<CachedNotificationPreferences?>? _inFlightSync;

  Future<CachedNotificationPreferences?> cached() async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    return _localStore.read(scope);
  }

  /// Records [enabled] for the ([eventType], [channelId]) cell locally and
  /// returns the updated snapshot. The cell stays pending (even if it now
  /// matches the last-known server value) until a sync confirms it, so a
  /// toggle-and-toggle-back during an in-flight request still converges on
  /// the latest value.
  ///
  /// Throws a [StateError] if there is no session or nothing cached yet —
  /// the screen only offers toggles once a matrix has loaded.
  Future<CachedNotificationPreferences> setPreference(
    String eventType,
    String channelId,
    bool enabled,
  ) async {
    final scope = await _cacheScope();
    if (scope == null) throw StateError('No signed-in account.');
    final updated = await _mutate(scope, (current) {
      final pending = copyCells(current.pending);
      pending.putIfAbsent(eventType, () => {})[channelId] = enabled;
      return current.copyWith(pending: pending);
    });
    if (updated == null) {
      throw StateError('Notification preferences have not been loaded.');
    }
    return updated;
  }

  /// Pushes every pending cell to the server, repeating until none are left
  /// (toggles made during a request go out in the next one). Concurrent
  /// callers share the same run. Returns the resulting snapshot, or `null`
  /// with no session or nothing cached.
  Future<CachedNotificationPreferences?> syncPending() {
    return _inFlightSync ??= _drainPending().whenComplete(
      () => _inFlightSync = null,
    );
  }

  Future<CachedNotificationPreferences?> _drainPending() async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    while (true) {
      final current = await _localStore.read(scope);
      if (current == null || !current.hasPending) return current;

      final sent = copyCells(current.pending);
      final NotificationPreferencesMatrix server;
      try {
        server = await _api.update(sent);
      } on NetworkException {
        rethrow;
      } on UnauthorizedException {
        rethrow;
      } on ApiException {
        await _mutate(
          scope,
          (c) => c.copyWith(pending: _withoutSent(c.pending, sent)),
        );
        rethrow;
      }

      await _mutate(
        scope,
        (c) => CachedNotificationPreferences(
          serverMatrix: server,
          fetchedAt: _clock(),
          pending: _withoutSent(c.pending, sent),
        ),
      );
    }
  }

  /// Syncs pending cells, then fetches the server matrix and caches it
  /// (keeping any cells toggled meanwhile as pending). A rejected sync
  /// doesn't stop the fetch; a `NetworkException` or 401 propagates.
  Future<CachedNotificationPreferences> refresh() async {
    try {
      await syncPending();
    } on NetworkException {
      rethrow;
    } on UnauthorizedException {
      rethrow;
    } on ApiException {
      // The rejected cells were dropped; the fetch below shows the server's
      // values for them.
    }

    final scope = await _cacheScope();
    final fresh = await _api.fetch();
    final fetchedAt = _clock();
    if (scope == null) {
      return CachedNotificationPreferences(
        serverMatrix: fresh,
        fetchedAt: fetchedAt,
      );
    }
    return _serialized(() async {
      final current = await _localStore.read(scope);
      final next = CachedNotificationPreferences(
        serverMatrix: fresh,
        fetchedAt: fetchedAt,
        pending: current?.pending ?? const {},
      );
      await _localStore.write(scope, next);
      return next;
    });
  }

  /// [pending] minus the cells whose value is still what was [sent] — a
  /// cell toggled again during the request stays pending.
  static PreferenceCells _withoutSent(
    PreferenceCells pending,
    PreferenceCells sent,
  ) {
    final remaining = copyCells(pending);
    sent.forEach((event, cells) {
      final row = remaining[event];
      if (row == null) return;
      cells.forEach((channel, value) {
        if (row[channel] == value) row.remove(channel);
      });
      if (row.isEmpty) remaining.remove(event);
    });
    return remaining;
  }

  Future<CachedNotificationPreferences?> _mutate(
    String scope,
    CachedNotificationPreferences Function(CachedNotificationPreferences) fn,
  ) {
    return _serialized(() async {
      final current = await _localStore.read(scope);
      if (current == null) return null;
      final next = fn(current);
      await _localStore.write(scope, next);
      return next;
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _storeLock.then((_) => action());
    _storeLock = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
