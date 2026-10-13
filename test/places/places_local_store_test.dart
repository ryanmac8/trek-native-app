import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/places/pending_place_op.dart';
import 'package:trek/places/place.dart';
import 'package:trek/places/places_local_store.dart';

void main() {
  group('PreferencesPlacesLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesPlacesLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesPlacesLocalStore();
    });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read('20'), isEmpty);
    });

    test("write() then read() round-trips a trip's places", () async {
      final places = [
        Place.fromJson({
          'id': 501,
          'trip_id': 20,
          'name': 'Fergburger',
          'category': {'id': 2, 'name': 'Restaurant', 'color': '#ef4444'},
        }),
      ];

      await store.write('20', places);
      final result = await store.read('20');

      expect(result, hasLength(1));
      expect(result.single.id, 501);
      expect(result.single.category?.name, 'Restaurant');
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', [
          Place.fromJson({'id': 1, 'trip_id': 20, 'name': 'A'}),
        ]);
        await store.write('20', [
          Place.fromJson({'id': 2, 'trip_id': 20, 'name': 'B'}),
        ]);

        final result = await store.read('20');

        expect(result, hasLength(1));
        expect(result.single.id, 2);
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', [
        Place.fromJson({'id': 1, 'trip_id': 20, 'name': 'A'}),
      ]);
      await store.write('21', [
        Place.fromJson({'id': 2, 'trip_id': 21, 'name': 'B'}),
      ]);

      expect((await store.read('20')).single.id, 1);
      expect((await store.read('21')).single.id, 2);
    });
  });

  group('PreferencesPlacesLocalStore pending outbox', () {
    late PreferencesPlacesLocalStore store;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      store = PreferencesPlacesLocalStore();
    });

    test('readPending() is empty when nothing is queued', () async {
      expect(await store.readPending('20'), isEmpty);
    });

    test('writePending() then readPending() round-trips the outbox', () async {
      await store.writePending('20', const [
        PendingPlaceOp(
          id: 'a',
          kind: PendingPlaceOpKind.create,
          placeId: -1,
          fields: {'name': 'Fergburger'},
        ),
        PendingPlaceOp(
          id: 'b',
          kind: PendingPlaceOpKind.update,
          placeId: 501,
          fields: {'notes': null},
          baseUpdatedAt: '2026-10-01 10:00:00',
          conflictServer: {'id': 501, 'trip_id': 20, 'name': 'Theirs'},
        ),
      ]);

      final ops = await store.readPending('20');

      expect(ops.map((op) => op.id), ['a', 'b']);
      expect(ops.first.kind, PendingPlaceOpKind.create);
      expect(ops.first.fields, {'name': 'Fergburger'});
      expect(ops.last.fields, {'notes': null});
      expect(ops.last.baseUpdatedAt, '2026-10-01 10:00:00');
      expect(ops.last.isConflicted, isTrue);
      expect(await store.readPending('21'), isEmpty);
    });

    test('writing an empty outbox clears it', () async {
      await store.writePending('20', const [
        PendingPlaceOp(id: 'a', kind: PendingPlaceOpKind.delete, placeId: 5),
      ]);
      await store.writePending('20', const []);

      expect(await store.readPending('20'), isEmpty);
    });
  });
}
