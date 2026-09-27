import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:trek/sync/outbox.dart';
import 'package:trek/sync/pending_write.dart';

import '../test_helpers.dart';

void main() {
  group('PendingWrite', () {
    test('round-trips through JSON', () {
      final write = PendingWrite(
        id: 'w1',
        kind: 'todo.update',
        payload: {'trip_id': 20, 'checked': true},
        coalesceKey: 'todo.update:7',
        createdAt: DateTime.utc(2026, 9, 27, 8),
        attempts: 2,
        lastError: 'Server error',
      );

      final decoded = PendingWrite.fromJson(write.toJson());

      expect(decoded.id, 'w1');
      expect(decoded.kind, 'todo.update');
      expect(decoded.payload, {'trip_id': 20, 'checked': true});
      expect(decoded.coalesceKey, 'todo.update:7');
      expect(decoded.createdAt, DateTime.utc(2026, 9, 27, 8));
      expect(decoded.attempts, 2);
      expect(decoded.lastError, 'Server error');
    });
  });

  group('Outbox', () {
    late InMemoryOutboxStore store;
    late Outbox outbox;

    setUp(() {
      store = InMemoryOutboxStore();
      outbox = Outbox(store: store);
    });

    test('queues writes in FIFO order and persists each one', () async {
      await outbox.enqueue('todo.create', {'name': 'a'});
      await outbox.enqueue('todo.create', {'name': 'b'});

      final pending = await outbox.pending();
      expect(pending.map((w) => w.payload['name']), ['a', 'b']);
      expect(store.writes.map((w) => w.payload['name']), ['a', 'b']);
      expect(pending.map((w) => w.id).toSet(), hasLength(2));
    });

    test('merges fields of writes sharing a coalesce key, keeping the '
        'earlier write\'s slot', () async {
      await outbox.enqueue('todo.update', {
        'name': 'Old',
        'checked': false,
      }, coalesceKey: 'todo:7');
      await outbox.enqueue('packing.update', {'checked': true});
      await outbox.enqueue('todo.update', {
        'checked': true,
      }, coalesceKey: 'todo:7');

      final pending = await outbox.pending();
      expect(pending, hasLength(2));
      expect(pending.first.kind, 'todo.update');
      expect(pending.first.payload, {'name': 'Old', 'checked': true});
    });

    test('replace swaps the queued payload instead of merging', () async {
      await outbox.enqueue('todo.reorder', {
        'order': [1, 2, 3],
        'extra': true,
      }, coalesceKey: 'todo.reorder:20');
      await outbox.enqueue(
        'todo.reorder',
        {
          'order': [3, 2, 1],
        },
        coalesceKey: 'todo.reorder:20',
        replace: true,
      );

      final pending = await outbox.pending();
      expect(pending.single.payload, {
        'order': [3, 2, 1],
      });
    });

    test('does not merge into a different kind with the same key', () async {
      await outbox.enqueue('todo.update', {'a': 1}, coalesceKey: 'todo:7');
      await outbox.enqueue('todo.delete', {}, coalesceKey: 'todo:7');

      expect(await outbox.pending(), hasLength(2));
    });

    test('does not merge into a write that is being pushed', () async {
      final first = await outbox.enqueue('todo.update', {
        'checked': true,
      }, coalesceKey: 'todo:7');
      outbox.markInFlight(first.id);

      await outbox.enqueue('todo.update', {
        'name': 'New',
      }, coalesceKey: 'todo:7');

      final pending = await outbox.pending();
      expect(pending, hasLength(2));
      expect(pending.first.payload, {'checked': true});
      expect(pending.last.payload, {'name': 'New'});
    });

    test('removeWhere drops matching writes and reports the count', () async {
      await outbox.enqueue('todo.create', {'local_id': 'x'});
      await outbox.enqueue('todo.update', {'local_id': 'x'});
      await outbox.enqueue('todo.create', {'local_id': 'y'});

      final removed = await outbox.removeWhere(
        (w) => w.payload['local_id'] == 'x',
      );

      expect(removed, 2);
      expect((await outbox.pending()).single.payload['local_id'], 'y');
      expect(store.writes, hasLength(1));
    });

    test('update records a failed attempt; ignores removed writes', () async {
      final write = await outbox.enqueue('todo.create', {});
      await outbox.update(write.copyWith(attempts: 1, lastError: 'boom'));
      expect((await outbox.pending()).single.attempts, 1);

      await outbox.remove(write.id);
      await outbox.update(write.copyWith(attempts: 2));
      expect(await outbox.pending(), isEmpty);
    });

    test('a new Outbox reloads writes persisted by an earlier one', () async {
      await outbox.enqueue('todo.create', {'name': 'survives restart'});

      final reloaded = Outbox(store: store);

      expect(
        (await reloaded.pending()).single.payload['name'],
        'survives restart',
      );
    });

    test('emits the pending count after each change', () async {
      final counts = <int>[];
      final subscription = outbox.changes.listen(counts.add);

      final write = await outbox.enqueue('a', {});
      await outbox.enqueue('b', {});
      await outbox.remove(write.id);
      await outbox.clear();
      await Future<void>.delayed(Duration.zero);

      expect(counts, [1, 2, 1, 0]);
      await subscription.cancel();
    });

    test('serializes concurrent enqueues without losing any', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) outbox.enqueue('todo.create', {'i': i}),
      ]);

      final pending = await outbox.pending();
      expect(pending.map((w) => w.payload['i']), List.generate(20, (i) => i));
    });
  });

  group('PreferencesOutboxStore', () {
    late InMemorySharedPreferencesAsync backend;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
    });

    test('persists and reads back the queue', () async {
      final store = PreferencesOutboxStore();
      final write = PendingWrite(
        id: 'w1',
        kind: 'todo.create',
        payload: {'name': 'Passport'},
        createdAt: DateTime.utc(2026, 9, 27),
      );

      await store.write([write]);
      final read = await PreferencesOutboxStore().read();

      expect(read.single.id, 'w1');
      expect(read.single.payload, {'name': 'Passport'});
    });

    test('an empty queue removes the key', () async {
      final store = PreferencesOutboxStore();
      await store.write([
        PendingWrite(
          id: 'w1',
          kind: 'k',
          payload: const {},
          createdAt: DateTime.utc(2026),
        ),
      ]);
      await store.write(const []);

      expect(
        await backend.getString(
          PreferencesOutboxStore.key,
          const SharedPreferencesOptions(),
        ),
        isNull,
      );
    });

    test('reads a corrupt value as an empty queue', () async {
      await backend.setString(
        PreferencesOutboxStore.key,
        'not json',
        const SharedPreferencesOptions(),
      );

      expect(await PreferencesOutboxStore().read(), isEmpty);
    });
  });
}
