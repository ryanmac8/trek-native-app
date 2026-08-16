import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/packing/packing_item.dart';
import 'package:trek/packing/packing_local_store.dart';

void main() {
  group('PreferencesPackingLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesPackingLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesPackingLocalStore();
    });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read('20'), isEmpty);
    });

    test("write() then read() round-trips a trip's packing items", () async {
      final items = [
        PackingItem.fromJson({
          'id': 501,
          'trip_id': 20,
          'name': 'Hiking boots',
          'category': 'Footwear',
          'checked': 1,
        }, tripId: '20'),
      ];

      await store.write('20', items);
      final result = await store.read('20');

      expect(result, hasLength(1));
      expect(result.single.id, 501);
      expect(result.single.category, 'Footwear');
      expect(result.single.checked, isTrue);
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', [
          PackingItem.fromJson({
            'id': 1,
            'trip_id': 20,
            'name': 'A',
          }, tripId: '20'),
        ]);
        await store.write('20', [
          PackingItem.fromJson({
            'id': 2,
            'trip_id': 20,
            'name': 'B',
          }, tripId: '20'),
        ]);

        final result = await store.read('20');

        expect(result, hasLength(1));
        expect(result.single.id, 2);
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', [
        PackingItem.fromJson({
          'id': 1,
          'trip_id': 20,
          'name': 'A',
        }, tripId: '20'),
      ]);
      await store.write('21', [
        PackingItem.fromJson({
          'id': 2,
          'trip_id': 21,
          'name': 'B',
        }, tripId: '21'),
      ]);

      expect((await store.read('20')).single.id, 1);
      expect((await store.read('21')).single.id, 2);
    });

    test(
      'a pending (offline-created) item round-trips with a null id',
      () async {
        const item = PackingItem(
          localId: 'local-1',
          tripId: '20',
          name: 'Draft',
        );

        await store.write('20', [item]);
        final result = await store.read('20');

        expect(result.single.id, isNull);
        expect(result.single.isPending, isTrue);
      },
    );
  });
}
