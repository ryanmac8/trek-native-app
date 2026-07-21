import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/days/day.dart';
import 'package:trek/days/days_local_store.dart';

void main() {
  group('PreferencesDaysLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesDaysLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesDaysLocalStore();
    });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read('20'), isEmpty);
    });

    test('write() then read() round-trips a trip\'s days', () async {
      final days = [
        Day.fromJson({
          'id': 101,
          'trip_id': 20,
          'day_number': 1,
          'date': '2026-11-28',
          'assignments': [
            {'id': 1},
          ],
        }),
      ];

      await store.write('20', days);
      final result = await store.read('20');

      expect(result, hasLength(1));
      expect(result.single.id, 101);
      expect(result.single.assignmentCount, 1);
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', [
          Day.fromJson({'id': 1, 'trip_id': 20, 'day_number': 1}),
        ]);
        await store.write('20', [
          Day.fromJson({'id': 2, 'trip_id': 20, 'day_number': 2}),
        ]);

        final result = await store.read('20');

        expect(result, hasLength(1));
        expect(result.single.id, 2);
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', [
        Day.fromJson({'id': 1, 'trip_id': 20, 'day_number': 1}),
      ]);
      await store.write('21', [
        Day.fromJson({'id': 2, 'trip_id': 21, 'day_number': 1}),
      ]);

      expect((await store.read('20')).single.id, 1);
      expect((await store.read('21')).single.id, 2);
    });
  });
}
