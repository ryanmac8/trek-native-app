import '../network/api_exception.dart';
import 'notifications_api.dart';
import 'notifications_local_store.dart';
import 'trek_notification.dart';

/// Offline-first front door for the notifications inbox (see
/// docs/offline-first.md). Screens use this, not [NotificationsApi]
/// directly, so the local cache stays the source of truth for what's shown
/// and "mark read" is applied locally before the network is involved.
///
/// Reads:
/// - [cachedNotifications] / [cachedUnreadCount] never touch the network —
///   safe for an instant first paint. Pending local reads are layered on
///   top so an optimistic "mark read" survives a restart.
/// - [refreshNotifications] flushes any queued reads, then fetches the
///   first page and caches it. On [NetworkException] it falls back to the
///   cache instead of failing, unless the cache is empty, in which case the
///   exception propagates so the caller can show an explicit offline state.
///
/// Writes ([markRead], [markAllRead]) apply to the cache first and enqueue
/// the id(s) in the local store's pending-reads outbox, then try to sync.
/// A [NetworkException] during sync is swallowed — the local write already
/// succeeded and the id stays queued for the next [refreshNotifications].
class NotificationsRepository {
  NotificationsRepository({
    required NotificationsApi notificationsApi,
    required NotificationsLocalStore localStore,
  }) : _api = notificationsApi,
       _localStore = localStore;

  final NotificationsApi _api;
  final NotificationsLocalStore _localStore;

  Future<List<TrekNotification>> cachedNotifications() async {
    final cached = await _localStore.readNotifications();
    final pending = await _localStore.readPendingReads();
    return _applyPendingReads(cached, pending);
  }

  Future<int> cachedUnreadCount() async {
    final notifications = await cachedNotifications();
    return notifications.where((n) => !n.isRead).length;
  }

  Future<List<TrekNotification>> refreshNotifications() async {
    try {
      await _flushPendingReads();
      final page = await _api.listInApp();
      final pending = await _localStore.readPendingReads();
      final merged = _applyPendingReads(page.notifications, pending);
      await _localStore.writeNotifications(merged);
      return merged;
    } on NetworkException {
      final cached = await cachedNotifications();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> markRead(int id) async {
    final cached = await _localStore.readNotifications();
    await _localStore.writeNotifications(_applyPendingReads(cached, {id}));

    final pending = await _localStore.readPendingReads();
    pending.add(id);
    await _localStore.writePendingReads(pending);

    try {
      await _api.markRead(id);
      pending.remove(id);
      await _localStore.writePendingReads(pending);
    } on NetworkException {
      // Local write already applied; the id stays queued for the next
      // refresh.
    } on ApiException {
      // 404 (already gone / not ours) or similar — nothing more to sync.
      pending.remove(id);
      await _localStore.writePendingReads(pending);
    }
  }

  Future<void> markAllRead() async {
    final cached = await _localStore.readNotifications();
    final unreadIds = cached.where((n) => !n.isRead).map((n) => n.id).toSet();
    if (unreadIds.isEmpty) return;

    await _localStore.writeNotifications(_applyPendingReads(cached, unreadIds));
    final pending = await _localStore.readPendingReads();
    pending.addAll(unreadIds);
    await _localStore.writePendingReads(pending);

    try {
      await _api.markAllRead();
      pending.removeAll(unreadIds);
      await _localStore.writePendingReads(pending);
    } on NetworkException {
      // Queued for the next refresh.
    }
  }

  /// Pushes queued reads to the server one at a time, narrowing the
  /// persisted queue as each succeeds so a mid-flush [NetworkException]
  /// leaves the rest queued. Non-network API errors (e.g. a 404 for a
  /// notification deleted server-side) count as done.
  Future<void> _flushPendingReads() async {
    final pending = await _localStore.readPendingReads();
    if (pending.isEmpty) return;
    final remaining = {...pending};
    for (final id in pending) {
      try {
        await _api.markRead(id);
      } on NetworkException {
        rethrow;
      } on ApiException {
        // treat as delivered
      }
      remaining.remove(id);
      await _localStore.writePendingReads(remaining);
    }
  }

  List<TrekNotification> _applyPendingReads(
    List<TrekNotification> notifications,
    Set<int> readIds,
  ) {
    if (readIds.isEmpty) return notifications;
    return [
      for (final n in notifications)
        if (!n.isRead && readIds.contains(n.id))
          n.copyWith(isRead: true)
        else
          n,
    ];
  }
}
