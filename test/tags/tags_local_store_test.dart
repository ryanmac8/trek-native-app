import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/tags/tag.dart';
import 'package:trek/tags/tags_local_store.dart';

void main() {
  group('PreferencesTagsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesTagsLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesTagsLocalStore();
    });

    test('read() returns an empty list when nothing has been cached', () async {
      expect(await store.read(), isEmpty);
    });

    test('write() then read() round-trips the tag list', () async {
      final tags = [
        Tag.fromJson({
          'id': 5,
          'user_id': 1,
          'name': 'Foodie',
          'color': '#ef4444',
        }),
      ];

      await store.write(tags);
      final result = await store.read();

      expect(result, hasLength(1));
      expect(result.single.id, 5);
      expect(result.single.name, 'Foodie');
      expect(result.single.color, '#ef4444');
    });

    test('write() overwrites what was previously cached', () async {
      await store.write([
        Tag.fromJson({'id': 1, 'user_id': 1, 'name': 'A'}),
      ]);
      await store.write([
        Tag.fromJson({'id': 2, 'user_id': 1, 'name': 'B'}),
      ]);

      final result = await store.read();

      expect(result, hasLength(1));
      expect(result.single.id, 2);
    });

    test('preserves a still-pending (no server id) tag', () async {
      await store.write(const [Tag(localId: 'local-1', name: 'Draft')]);

      final result = await store.read();

      expect(result.single.isPending, isTrue);
      expect(result.single.localId, 'local-1');
    });
  });
}
