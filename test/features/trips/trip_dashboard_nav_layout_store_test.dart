import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/features/trips/trip_dashboard_nav_layout_store.dart';

void main() {
  group('PreferencesTripDashboardNavLayoutStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesTripDashboardNavLayoutStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesTripDashboardNavLayoutStore();
    });

    test('read() returns null when nothing has been customized yet', () async {
      expect(await store.read(), isNull);
    });

    test(
      'write() then read() round-trips slot keys, including empty slots',
      () async {
        await store.write(['todos', null, 'book', 'files']);

        expect(await store.read(), ['todos', null, 'book', 'files']);
      },
    );

    test('write() overwrites what was previously saved', () async {
      await store.write(['days', 'places', 'budget', 'packing']);
      await store.write(['todos', 'book', 'lists', 'collab']);

      expect(await store.read(), ['todos', 'book', 'lists', 'collab']);
    });
  });
}
