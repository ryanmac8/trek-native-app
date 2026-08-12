import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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
}
