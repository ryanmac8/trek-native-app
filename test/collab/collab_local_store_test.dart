import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/collab/collab_local_store.dart';
import 'package:trek/collab/collab_note.dart';

void main() {
  group('PreferencesCollabLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesCollabLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesCollabLocalStore();
    });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read('20'), isEmpty);
    });

    test("write() then read() round-trips a trip's notes", () async {
      final notes = [
        CollabNote.fromJson({
          'id': 501,
          'trip_id': 20,
          'title': 'Packing reminders',
          'category': 'Logistics',
          'pinned': 1,
        }, tripId: '20'),
      ];

      await store.write('20', notes);
      final result = await store.read('20');

      expect(result, hasLength(1));
      expect(result.single.id, 501);
      expect(result.single.category, 'Logistics');
      expect(result.single.pinned, isTrue);
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', [
          CollabNote.fromJson({
            'id': 1,
            'trip_id': 20,
            'title': 'A',
          }, tripId: '20'),
        ]);
        await store.write('20', [
          CollabNote.fromJson({
            'id': 2,
            'trip_id': 20,
            'title': 'B',
          }, tripId: '20'),
        ]);

        final result = await store.read('20');

        expect(result, hasLength(1));
        expect(result.single.id, 2);
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', [
        CollabNote.fromJson({
          'id': 1,
          'trip_id': 20,
          'title': 'A',
        }, tripId: '20'),
      ]);
      await store.write('21', [
        CollabNote.fromJson({
          'id': 2,
          'trip_id': 21,
          'title': 'B',
        }, tripId: '21'),
      ]);

      expect((await store.read('20')).single.id, 1);
      expect((await store.read('21')).single.id, 2);
    });

    test(
      'a pending (offline-created) note round-trips with a null id',
      () async {
        const note = CollabNote(
          localId: 'local-1',
          tripId: '20',
          title: 'Draft',
        );

        await store.write('20', [note]);
        final result = await store.read('20');

        expect(result.single.id, isNull);
        expect(result.single.isPending, isTrue);
      },
    );
  });
}
