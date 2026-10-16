import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/places/categories_local_store.dart';
import 'package:trek/places/place.dart';

void main() {
  group('PreferencesCategoriesLocalStore', () {
    late PreferencesCategoriesLocalStore store;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      store = PreferencesCategoriesLocalStore();
    });

    test('read() is empty when nothing has been cached', () async {
      expect(await store.read(), isEmpty);
    });

    test('write() then read() round-trips the list in order', () async {
      await store.write(const [
        PlaceCategoryRef(
          id: 2,
          name: 'Restaurant',
          color: '#ef4444',
          icon: '🍽️',
        ),
        PlaceCategoryRef(id: 11, name: 'Wineries', icon: 'MapPin'),
      ]);

      final result = await store.read();

      expect(result.map((c) => c.id), [2, 11]);
      expect(result.first.color, '#ef4444');
      expect(result.first.icon, '🍽️');
      expect(result.last.color, isNull);
    });

    test('write() replaces the previous list', () async {
      await store.write(const [PlaceCategoryRef(id: 2, name: 'Restaurant')]);
      await store.write(const [PlaceCategoryRef(id: 3, name: 'Attraction')]);

      expect((await store.read()).single.id, 3);
    });
  });
}
