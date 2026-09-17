import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/weather/weather_local_store.dart';
import 'package:trek/weather/weather_models.dart';

void main() {
  late InMemorySharedPreferencesAsync backend;
  late DateTime now;
  late PreferencesWeatherLocalStore store;

  setUp(() {
    backend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backend;
    now = DateTime(2026, 9, 1, 12);
    store = PreferencesWeatherLocalStore(clock: () => now);
  });

  WeatherReport report(String type) => WeatherReport.fromJson({
    'temp': 18,
    'main': 'Clouds',
    'description': 'Overcast',
    'type': type,
  });

  test('read returns null for a key that was never written', () async {
    expect(await store.read('nope'), isNull);
  });

  test('write then read round-trips the report', () async {
    await store.write('paris_current', report('current'));

    final cached = await store.read('paris_current');

    expect(cached?.report.condition, 'Clouds');
    expect(cached?.isFresh, isTrue);
  });

  test('a forecast entry is fresh for an hour, then stale', () async {
    await store.write('key', report('forecast'));

    now = now.add(const Duration(minutes: 59));
    expect((await store.read('key'))?.isFresh, isTrue);

    now = now.add(const Duration(minutes: 2));
    final cached = await store.read('key');
    expect(cached, isNotNull);
    expect(cached!.isFresh, isFalse, reason: 'kept for offline fallback');
  });

  test('current conditions expire after 15 minutes', () async {
    await store.write('key', report('current'));

    now = now.add(const Duration(minutes: 16));

    expect((await store.read('key'))?.isFresh, isFalse);
  });

  test('climate estimates stay fresh for a day', () async {
    await store.write('key', report('climate'));

    now = now.add(const Duration(hours: 23));

    expect((await store.read('key'))?.isFresh, isTrue);
  });

  test('evicts the oldest entry once past the 60-entry cap', () async {
    for (var i = 0; i < 65; i++) {
      await store.write('k$i', report('forecast'));
    }

    expect(await store.read('k0'), isNull);
    expect(await store.read('k4'), isNull);
    expect(await store.read('k64'), isNotNull);
  });
}
