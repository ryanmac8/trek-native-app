/// What [SyncEngine] is currently doing about the outbox.
enum SyncPhase {
  /// Nothing queued, or the last drain emptied the queue.
  idle,

  /// A drain is pushing queued writes.
  syncing,

  /// The last push couldn't reach the server; retrying with backoff.
  offline,

  /// The server answered 408/429/5xx; retrying with backoff.
  retrying,

  /// The server answered 401. Writes stay queued until the next login or
  /// app resume triggers a drain.
  authRequired,
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.nextRetryAt,
  });

  final SyncPhase phase;

  /// Writes still in the outbox.
  final int pendingCount;

  /// When a drain last emptied the queue.
  final DateTime? lastSyncedAt;

  /// When the next automatic retry fires, while [phase] is
  /// [SyncPhase.offline] or [SyncPhase.retrying].
  final DateTime? nextRetryAt;

  bool get hasPending => pendingCount > 0;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? pendingCount,
    DateTime? lastSyncedAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.pendingCount == pendingCount &&
      other.lastSyncedAt == lastSyncedAt &&
      other.nextRetryAt == nextRetryAt;

  @override
  int get hashCode =>
      Object.hash(phase, pendingCount, lastSyncedAt, nextRetryAt);

  @override
  String toString() =>
      'SyncStatus($phase, pending: $pendingCount, '
      'lastSyncedAt: $lastSyncedAt, nextRetryAt: $nextRetryAt)';
}
