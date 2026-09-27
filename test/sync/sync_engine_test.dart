import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/sync/outbox.dart';
import 'package:trek/sync/pending_write.dart';
import 'package:trek/sync/sync_engine.dart';
import 'package:trek/sync/sync_policy.dart';
import 'package:trek/sync/sync_status.dart';

import '../test_helpers.dart';

/// Records every push and answers with the next queued outcome (an error
/// to throw, or a [Completer] to wait on); succeeds once none are queued.
class FakeHandler extends SyncHandler {
  final pushed = <PendingWrite>[];
  final rejected = <(PendingWrite, Object)>[];
  final outcomes = <Object>[];

  @override
  Future<void> push(PendingWrite write) async {
    pushed.add(write);
    if (outcomes.isEmpty) return;
    final outcome = outcomes.removeAt(0);
    if (outcome is Completer<void>) return outcome.future;
    throw outcome;
  }

  @override
  Future<void> onRejected(PendingWrite write, Object error) async {
    rejected.add((write, error));
  }
}

/// Always rejected by the server, and its rollback fails too.
class ThrowingRollbackHandler extends SyncHandler {
  @override
  Future<void> push(PendingWrite write) async =>
      throw const ForbiddenException();

  @override
  Future<void> onRejected(PendingWrite write, Object error) async =>
      throw StateError('rollback failed');
}

void main() {
  const policy = SyncPolicy(
    baseDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 60),
    maxAttempts: 3,
  );

  late InMemoryOutboxStore store;
  late Outbox outbox;
  late FakeHandler handler;
  late SyncEngine engine;
  late DateTime now;

  SyncEngine buildEngine() => SyncEngine(
    outbox: outbox,
    handlers: {'todo.update': handler},
    policy: policy,
    clock: () => now,
  );

  setUp(() {
    store = InMemoryOutboxStore();
    outbox = Outbox(store: store);
    handler = FakeHandler();
    now = DateTime.utc(2026, 9, 27, 9);
    engine = buildEngine();
  });

  // Engines built by runFake are disposed inside their fake zone instead.
  var fake = false;
  tearDown(() async {
    if (!fake) await engine.dispose();
    fake = false;
  });

  // Timers and futures only run on fake time if the objects that create
  // them are built inside the fake zone too.
  void runFake(void Function(FakeAsync async) body) {
    fake = true;
    fakeAsync((async) {
      store = InMemoryOutboxStore();
      outbox = Outbox(store: store);
      handler = FakeHandler();
      engine = buildEngine();
      body(async);
      engine.dispose();
      async.flushMicrotasks();
    });
  }

  Future<void> enqueue(String name, {String? coalesceKey}) =>
      outbox.enqueue('todo.update', {'name': name}, coalesceKey: coalesceKey);

  List<Object?> names(List<PendingWrite> writes) =>
      writes.map((w) => w.payload['name']).toList();

  test('pushes queued writes in order and empties the outbox', () async {
    await enqueue('a');
    await enqueue('b');

    await engine.drain();

    expect(names(handler.pushed), ['a', 'b']);
    expect(await outbox.pending(), isEmpty);
    expect(store.writes, isEmpty);
    expect(engine.status.phase, SyncPhase.idle);
    expect(engine.status.pendingCount, 0);
    expect(engine.status.lastSyncedAt, now);
  });

  test('writes persisted before launch are pushed by start()', () async {
    store.writes = [
      PendingWrite(
        id: 'old',
        kind: 'todo.update',
        payload: {'name': 'from last session'},
        createdAt: DateTime.utc(2026, 9, 26),
      ),
    ];
    outbox = Outbox(store: store);
    engine = buildEngine();

    await engine.start();

    expect(names(handler.pushed), ['from last session']);
    expect(store.writes, isEmpty);
  });

  test('offline: keeps the write, stops the drain, and retries with '
      'backoff until the network is back', () {
    runFake((async) {
      handler.outcomes.addAll([
        const NetworkException(),
        const NetworkException(),
      ]);
      enqueue('a');
      enqueue('b');
      async.flushMicrotasks();

      engine.drain();
      async.flushMicrotasks();

      // Stopped at the first write; the second was never attempted.
      expect(names(handler.pushed), ['a']);
      expect(engine.status.phase, SyncPhase.offline);
      expect(engine.status.pendingCount, 2);
      expect(engine.status.nextRetryAt, now.add(const Duration(seconds: 2)));

      async.elapse(const Duration(seconds: 2));
      expect(names(handler.pushed), ['a', 'a']);
      expect(engine.status.phase, SyncPhase.offline);
      expect(engine.status.nextRetryAt, now.add(const Duration(seconds: 4)));

      async.elapse(const Duration(seconds: 3));
      expect(handler.pushed, hasLength(2), reason: 'backoff doubled to 4s');

      async.elapse(const Duration(seconds: 1));
      expect(names(handler.pushed), ['a', 'a', 'a', 'b']);
      expect(engine.status.phase, SyncPhase.idle);
      expect(store.writes, isEmpty);
    });
  });

  test('offline failures do not count against a write\'s attempts', () {
    runFake((async) {
      handler.outcomes.addAll(List.filled(50, const NetworkException()));
      enqueue('a');
      async.flushMicrotasks();

      engine.drain();
      async.elapse(const Duration(minutes: 5));

      expect(handler.pushed.length, greaterThan(policy.maxAttempts));
      expect(handler.rejected, isEmpty);
      expect(store.writes.single.attempts, 0);
    });
  });

  test('a rejected write is dropped, rolled back via onRejected, reported, '
      'and the drain continues', () async {
    handler.outcomes.add(const ValidationException('Name is required'));
    final rejections = <SyncRejection>[];
    final subscription = engine.rejections.listen(rejections.add);

    await enqueue('bad');
    await enqueue('good');
    await engine.drain();
    await Future<void>.delayed(Duration.zero);

    expect(names(handler.pushed), ['bad', 'good']);
    expect(handler.rejected.single.$1.payload['name'], 'bad');
    expect(handler.rejected.single.$2, isA<ValidationException>());
    expect(rejections.single.write.payload['name'], 'bad');
    expect(store.writes, isEmpty);
    expect(engine.status.phase, SyncPhase.idle);
    await subscription.cancel();
  });

  test('transient server errors retry with backoff and count attempts, '
      'then give up after maxAttempts', () {
    runFake((async) {
      handler.outcomes.addAll([
        const ServerException(503, 'Unavailable'),
        const ServerException(500, 'Oops'),
        const ServerException(500, 'Oops'),
      ]);
      enqueue('a');
      async.flushMicrotasks();

      engine.drain();
      async.flushMicrotasks();
      expect(engine.status.phase, SyncPhase.retrying);
      expect(store.writes.single.attempts, 1);
      expect(store.writes.single.lastError, 'Unavailable');

      async.elapse(const Duration(seconds: 2));
      expect(store.writes.single.attempts, 2);

      async.elapse(const Duration(seconds: 4));
      expect(handler.pushed, hasLength(3));
      expect(handler.rejected, hasLength(1));
      expect(store.writes, isEmpty);
      expect(engine.status.phase, SyncPhase.idle);
    });
  });

  test('401 holds writes without scheduling a retry until drained again', () {
    runFake((async) {
      handler.outcomes.add(const UnauthorizedException());
      engine.start();
      enqueue('a');
      async.flushMicrotasks();

      expect(engine.status.phase, SyncPhase.authRequired);
      expect(engine.status.nextRetryAt, isNull);

      // Neither time passing nor a new edit hits the server while signed
      // out.
      async.elapse(const Duration(minutes: 10));
      enqueue('b');
      async.flushMicrotasks();
      expect(handler.pushed, hasLength(1));

      engine.drain(); // e.g. after logging back in
      async.flushMicrotasks();
      expect(names(handler.pushed), ['a', 'a', 'b']);
      expect(engine.status.phase, SyncPhase.idle);
    });
  });

  test('after start(), enqueuing a write drains it automatically', () {
    runFake((async) {
      engine.start();
      async.flushMicrotasks();
      expect(engine.status.phase, SyncPhase.idle);

      enqueue('a');
      async.flushMicrotasks();

      expect(names(handler.pushed), ['a']);
      expect(store.writes, isEmpty);
    });
  });

  test('while backing off, new writes wait for the scheduled retry', () {
    runFake((async) {
      handler.outcomes.add(const NetworkException());
      engine.start();
      enqueue('a');
      async.flushMicrotasks();
      expect(engine.status.phase, SyncPhase.offline);

      enqueue('b');
      async.flushMicrotasks();
      expect(handler.pushed, hasLength(1));
      expect(engine.status.pendingCount, 2);

      async.elapse(const Duration(seconds: 2));
      expect(names(handler.pushed), ['a', 'a', 'b']);
    });
  });

  test('an edit made while its write is in flight is queued separately, '
      'not merged into the already-sent payload', () {
    runFake((async) {
      final inFlight = Completer<void>();
      handler.outcomes.add(inFlight);
      enqueue('first', coalesceKey: 'todo:7');
      async.flushMicrotasks();

      engine.drain();
      async.flushMicrotasks();
      enqueue('second', coalesceKey: 'todo:7');
      async.flushMicrotasks();

      inFlight.complete();
      async.flushMicrotasks();

      expect(names(handler.pushed), ['first', 'second']);
      expect(store.writes, isEmpty);
    });
  });

  test('concurrent drain() calls push each write once', () async {
    await enqueue('a');
    await enqueue('b');

    await Future.wait([engine.drain(), engine.drain(), engine.drain()]);

    expect(names(handler.pushed), ['a', 'b']);
  });

  test('a rollback that throws still reports the rejection and keeps '
      'draining', () async {
    await engine.dispose();
    engine = SyncEngine(
      outbox: outbox,
      handlers: {'todo.update': handler, 'broken': ThrowingRollbackHandler()},
      policy: policy,
      clock: () => now,
    );
    final rejections = <SyncRejection>[];
    final subscription = engine.rejections.listen(rejections.add);
    await outbox.enqueue('broken', {});
    await enqueue('a');

    await engine.drain();
    await Future<void>.delayed(Duration.zero);

    expect(rejections.single.write.kind, 'broken');
    expect(names(handler.pushed), ['a']);
    expect(engine.status.phase, SyncPhase.idle);
    await subscription.cancel();
  });

  test('a write with no registered handler is rejected, not stuck', () async {
    await outbox.enqueue('unknown.kind', {});
    await enqueue('a');
    final rejections = <SyncRejection>[];
    final subscription = engine.rejections.listen(rejections.add);

    await engine.drain();
    await Future<void>.delayed(Duration.zero);

    expect(rejections.single.write.kind, 'unknown.kind');
    expect(rejections.single.error, isA<StateError>());
    expect(names(handler.pushed), ['a']);
    await subscription.cancel();
  });

  test('statusChanges reports syncing then idle', () async {
    final phases = <SyncPhase>[];
    final subscription = engine.statusChanges.listen(
      (s) => phases.add(s.phase),
    );
    await enqueue('a');

    await engine.drain();
    await Future<void>.delayed(Duration.zero);

    expect(phases, [SyncPhase.syncing, SyncPhase.idle]);
    await subscription.cancel();
  });
}
