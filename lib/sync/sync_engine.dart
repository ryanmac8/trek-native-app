import 'dart:async';

import 'outbox.dart';
import 'pending_write.dart';
import 'sync_policy.dart';
import 'sync_status.dart';

/// Pushes one kind of queued write to the server. Registered with
/// [SyncEngine] under the [PendingWrite.kind] it handles.
abstract class SyncHandler {
  /// Sends [write] to the server and reconciles the feature's local cache
  /// with the response (e.g. swapping a local id for the server's). Throw
  /// the [ApiClient]'s [ApiException] unchanged so [SyncPolicy] can
  /// classify it.
  Future<void> push(PendingWrite write);

  /// Called once when [write] is dropped as [SyncFailure.rejected], so the
  /// feature can roll back its optimistic local change.
  Future<void> onRejected(PendingWrite write, Object error) async {}
}

/// A write the server refused, dropped from the outbox.
class SyncRejection {
  const SyncRejection(this.write, this.error);

  final PendingWrite write;
  final Object error;
}

/// Drains the [Outbox] in FIFO order through the registered [SyncHandler]s.
///
/// A drain stops at the first write that fails for a reason other than
/// [SyncFailure.rejected], so later writes never overtake an earlier write
/// to the same entity. Offline and transient failures schedule an automatic
/// retry with [SyncPolicy.delayFor] backoff; an auth failure waits for
/// [drain] to be called again (login, app resume).
///
/// Enqueuing a write triggers a drain on its own once [start] has run.
class SyncEngine {
  SyncEngine({
    required Outbox outbox,
    required Map<String, SyncHandler> handlers,
    SyncPolicy policy = const SyncPolicy(),
    DateTime Function()? clock,
  }) : _outbox = outbox,
       _handlers = handlers,
       _policy = policy,
       _clock = clock ?? DateTime.now;

  final Outbox _outbox;
  final Map<String, SyncHandler> _handlers;
  final SyncPolicy _policy;
  final DateTime Function() _clock;

  final _statusController = StreamController<SyncStatus>.broadcast();
  final _rejections = StreamController<SyncRejection>.broadcast();

  SyncStatus _status = const SyncStatus();
  StreamSubscription<int>? _outboxSubscription;
  Future<void>? _drain;
  bool _drainAgain = false;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;
  bool _disposed = false;

  SyncStatus get status => _status;

  /// Emits every [status] change.
  Stream<SyncStatus> get statusChanges => _statusController.stream;

  /// Emits each write dropped as [SyncFailure.rejected].
  Stream<SyncRejection> get rejections => _rejections.stream;

  /// Loads the persisted queue's size, starts listening for new writes, and
  /// runs a first drain.
  Future<void> start() async {
    _outboxSubscription ??= _outbox.changes.listen((count) {
      final grew = count > _status.pendingCount;
      _setStatus(_status.copyWith(pendingCount: count));
      // A new write while backing off (or signed out) waits for the
      // scheduled retry or the next explicit drain, rather than hitting the
      // server once per edit.
      if (grew &&
          _retryTimer == null &&
          _status.phase != SyncPhase.authRequired) {
        unawaited(drain());
      }
    });
    _setStatus(
      _status.copyWith(pendingCount: (await _outbox.pending()).length),
    );
    await drain();
  }

  /// Pushes queued writes until the queue is empty or a push fails. If a
  /// drain is already running, it runs once more afterwards and this
  /// returns when that pass completes. Cancels any scheduled retry.
  Future<void> drain() {
    if (_disposed) return Future.value();
    final running = _drain;
    if (running != null) {
      _drainAgain = true;
      return running;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    final drain = _run().whenComplete(() => _drain = null);
    _drain = drain;
    return drain;
  }

  Future<void> _run() async {
    do {
      _drainAgain = false;
      if (!await _drainOnce()) return;
    } while (_drainAgain && !_disposed);
  }

  /// Returns whether the queue was emptied.
  Future<bool> _drainOnce() async {
    var queue = await _outbox.pending();
    if (queue.isNotEmpty) {
      _setStatus(
        _status.copyWith(
          phase: SyncPhase.syncing,
          pendingCount: queue.length,
          clearNextRetryAt: true,
        ),
      );
    }

    while (queue.isNotEmpty && !_disposed) {
      final write = queue.first;
      final failure = await _push(write);
      if (failure != null) {
        _onStopped(failure);
        return false;
      }
      queue = await _outbox.pending();
    }

    _consecutiveFailures = 0;
    _setStatus(
      _status.copyWith(
        phase: SyncPhase.idle,
        pendingCount: 0,
        lastSyncedAt: _clock(),
        clearNextRetryAt: true,
      ),
    );
    return true;
  }

  /// Pushes [write]; returns the failure that should stop the drain, or
  /// null to keep going (pushed, or rejected and dropped).
  Future<SyncFailure?> _push(PendingWrite write) async {
    final handler = _handlers[write.kind];
    if (handler == null) {
      await _reject(
        write,
        null,
        StateError('No SyncHandler for "${write.kind}".'),
      );
      return null;
    }

    _outbox.markInFlight(write.id);
    try {
      await handler.push(write);
      _outbox.markInFlight(null);
      await _outbox.remove(write.id);
      return null;
    } catch (error) {
      _outbox.markInFlight(null);
      var failure = _policy.classify(error);
      if (failure == SyncFailure.transient) {
        final attempts = write.attempts + 1;
        if (attempts >= _policy.maxAttempts) {
          failure = SyncFailure.rejected;
        } else {
          await _outbox.update(
            write.copyWith(attempts: attempts, lastError: '$error'),
          );
        }
      }
      if (failure == SyncFailure.rejected) {
        await _reject(write, handler, error);
        return null;
      }
      return failure;
    }
  }

  Future<void> _reject(
    PendingWrite write,
    SyncHandler? handler,
    Object error,
  ) async {
    await _outbox.remove(write.id);
    try {
      await handler?.onRejected(write, error);
    } catch (_) {
      // A failed rollback mustn't wedge the drain; the rejection is still
      // reported below so the user learns the change didn't save.
    }
    if (!_rejections.isClosed) _rejections.add(SyncRejection(write, error));
  }

  void _onStopped(SyncFailure failure) {
    if (failure == SyncFailure.unauthorized) {
      _setStatus(
        _status.copyWith(phase: SyncPhase.authRequired, clearNextRetryAt: true),
      );
      return;
    }
    _consecutiveFailures++;
    final delay = _policy.delayFor(_consecutiveFailures);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(drain());
    });
    _setStatus(
      _status.copyWith(
        phase: failure == SyncFailure.offline
            ? SyncPhase.offline
            : SyncPhase.retrying,
        nextRetryAt: _clock().add(delay),
      ),
    );
  }

  void _setStatus(SyncStatus status) {
    if (status == _status || _disposed) return;
    _status = status;
    _statusController.add(status);
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _outboxSubscription?.cancel();
    await _statusController.close();
    await _rejections.close();
  }
}
