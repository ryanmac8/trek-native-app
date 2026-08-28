import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/reservations/reservation.dart';
import 'package:trek/reservations/reservations_local_store.dart';

void main() {
  group('PreferencesReservationsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesReservationsLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesReservationsLocalStore();
    });

    Reservation booking(int id, {String title = 'Booking'}) =>
        Reservation.fromJson({
          'id': id,
          'trip_id': 20,
          'title': title,
          'type': 'flight',
          'status': 'confirmed',
        });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read('20'), isEmpty);
    });

    test("write() then read() round-trips a trip's reservations", () async {
      await store.write('20', [booking(7, title: 'NZ201')]);
      final result = await store.read('20');

      expect(result, hasLength(1));
      expect(result.single.id, 7);
      expect(result.single.title, 'NZ201');
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', [booking(1)]);
        await store.write('20', [booking(2)]);

        final result = await store.read('20');

        expect(result, hasLength(1));
        expect(result.single.id, 2);
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', [booking(1)]);
      await store.write('21', [booking(2)]);

      expect((await store.read('20')).single.id, 1);
      expect((await store.read('21')).single.id, 2);
    });
  });
}
