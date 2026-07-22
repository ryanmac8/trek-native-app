import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/trips/trip.dart';
import 'package:trek/trips/trips_local_store.dart';

void main() {
  group('PreferencesTripsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesTripsLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesTripsLocalStore();
    });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read(), isEmpty);
    });

    test('write() then read() round-trips synced and pending trips', () async {
      final trips = [
        Trip.fromJson({'id': 20, 'title': 'New Zealand', 'day_count': 16}),
        const Trip(localId: 'local-1', title: 'Draft trip'),
      ];

      await store.write(trips);
      final result = await store.read();

      expect(result, hasLength(2));
      expect(result[0].id, 20);
      expect(result[0].isPending, isFalse);
      expect(result[1].localId, 'local-1');
      expect(result[1].isPending, isTrue);
    });

    test('write() overwrites what was previously cached', () async {
      await store.write([
        Trip.fromJson({'id': 1, 'title': 'First'}),
      ]);
      await store.write([
        Trip.fromJson({'id': 2, 'title': 'Second'}),
      ]);

      final result = await store.read();

      expect(result, hasLength(1));
      expect(result.single.title, 'Second');
    });

    test(
      'readPendingDeletes() returns an empty set when nothing is queued',
      () async {
        expect(await store.readPendingDeletes(), isEmpty);
      },
    );

    test(
      'writePendingDeletes() then readPendingDeletes() round-trips',
      () async {
        await store.writePendingDeletes({1, 2, 3});

        expect(await store.readPendingDeletes(), {1, 2, 3});
      },
    );
  });
}
