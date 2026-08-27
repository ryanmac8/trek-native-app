import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/accommodations/accommodation.dart';
import 'package:trek/accommodations/accommodations_local_store.dart';

void main() {
  group('PreferencesAccommodationsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesAccommodationsLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesAccommodationsLocalStore();
    });

    Accommodation stay(int id, {String name = 'Hotel'}) =>
        Accommodation.fromJson({
          'id': id,
          'trip_id': 20,
          'place_id': id * 10,
          'start_day_id': 1,
          'end_day_id': 2,
          'place_name': name,
        });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read('20'), isEmpty);
    });

    test("write() then read() round-trips a trip's accommodations", () async {
      await store.write('20', [stay(7, name: 'Sofitel')]);
      final result = await store.read('20');

      expect(result, hasLength(1));
      expect(result.single.id, 7);
      expect(result.single.placeName, 'Sofitel');
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', [stay(1)]);
        await store.write('20', [stay(2)]);

        final result = await store.read('20');

        expect(result, hasLength(1));
        expect(result.single.id, 2);
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', [stay(1)]);
      await store.write('21', [stay(2)]);

      expect((await store.read('20')).single.id, 1);
      expect((await store.read('21')).single.id, 2);
    });
  });
}
