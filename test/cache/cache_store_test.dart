import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/cache/cache_entry.dart';
import 'package:trek/cache/cache_store.dart';

void main() {
  late PreferencesCacheStore store;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = PreferencesCacheStore();
  });

  final entry = CacheEntry(
    data: {
      'trips': [
        {'id': 20, 'title': 'New Zealand'},
      ],
    },
    fetchedAt: DateTime.utc(2026, 10, 9, 12),
    schemaVersion: 3,
    etag: 'W/"38-abc"',
    invalidated: true,
  );

  test('round-trips an entry', () async {
    await store.write('https://trek.example.com#7|trips', entry);

    final read = (await store.read('https://trek.example.com#7|trips'))!;

    expect(read.data, entry.data);
    expect(read.fetchedAt, entry.fetchedAt);
    expect(read.schemaVersion, 3);
    expect(read.etag, 'W/"38-abc"');
    expect(read.invalidated, isTrue);
  });

  test('lists only its own keys, without the prefix', () async {
    await store.write('s|trips', entry);
    await SharedPreferencesAsync().setString('trek.server.public_url', 'x');

    expect(await store.keys(), {'s|trips'});
  });

  test('removes an entry', () async {
    await store.write('s|trips', entry);

    await store.remove('s|trips');

    expect(await store.read('s|trips'), isNull);
  });

  test('reads a corrupt entry as a miss', () async {
    await SharedPreferencesAsync().setString('trek.cache.s|trips', '{oops');
    await SharedPreferencesAsync().setString(
      'trek.cache.s|days',
      '{"data": 1}',
    );

    expect(await store.read('s|trips'), isNull);
    expect(await store.read('s|days'), isNull);
  });
}
