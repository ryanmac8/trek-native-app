import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/maps/maps_local_store.dart';
import 'package:trek/maps/maps_models.dart';

void main() {
  group('PreferencesMapsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late DateTime now;
    late PreferencesMapsLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      now = DateTime(2026, 1, 1);
      store = PreferencesMapsLocalStore(clock: () => now);
    });

    test('reading a never-written key returns null', () async {
      expect(await store.readReverseGeocode('missing'), isNull);
      expect(await store.readResolvedPlace('missing'), isNull);
    });

    test('reverse-geocode entries round-trip and read back fresh', () async {
      const result = ReverseGeocodeResult(
        name: 'Eiffel Tower',
        address: 'Paris, France',
      );
      await store.writeReverseGeocode('48.85660_2.35220', result);

      final cached = await store.readReverseGeocode('48.85660_2.35220');

      expect(cached, isNotNull);
      expect(cached!.result.name, 'Eiffel Tower');
      expect(cached.isFresh, isTrue);
    });

    test('resolved-place entries round-trip and read back fresh', () async {
      const place = ResolvedPlace(
        point: LatLng(48.8584, 2.2945),
        name: 'Eiffel Tower',
        address: 'Paris, France',
        googleFtid: 'abc',
      );
      await store.writeResolvedPlace('https://maps.app.goo.gl/abc', place);

      final cached = await store.readResolvedPlace(
        'https://maps.app.goo.gl/abc',
      );

      expect(cached, isNotNull);
      expect(cached!.place.point, place.point);
      expect(cached.place.googleFtid, 'abc');
      expect(cached.isFresh, isTrue);
    });

    test('an entry past its TTL is still returned but marked stale', () async {
      const result = ReverseGeocodeResult(name: 'Old Answer', address: null);
      await store.writeReverseGeocode('key', result);

      now = now.add(const Duration(days: 8));

      final cached = await store.readReverseGeocode('key');

      expect(cached, isNotNull);
      expect(cached!.isFresh, isFalse);
      expect(cached.result.name, 'Old Answer');
    });

    test('the two caches (reverse and resolve-url) do not collide', () async {
      await store.writeReverseGeocode(
        'same-key',
        const ReverseGeocodeResult(name: 'Reverse answer'),
      );
      await store.writeResolvedPlace(
        'same-key',
        const ResolvedPlace(point: LatLng(1, 2), name: 'Resolved answer'),
      );

      expect(
        (await store.readReverseGeocode('same-key'))!.result.name,
        'Reverse answer',
      );
      expect(
        (await store.readResolvedPlace('same-key'))!.place.name,
        'Resolved answer',
      );
    });
  });
}
