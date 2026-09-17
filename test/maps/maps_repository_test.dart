import 'package:flutter_test/flutter_test.dart';
import 'package:trek/maps/maps_api.dart';
import 'package:trek/maps/maps_local_store.dart';
import 'package:trek/maps/maps_models.dart';
import 'package:trek/maps/maps_repository.dart';
import 'package:trek/network/api_exception.dart';

/// In-memory [MapsLocalStore] fake — no shared_preferences platform channel
/// involved, mirroring [InMemoryTokenStorage] in test_helpers.dart.
class _InMemoryMapsLocalStore implements MapsLocalStore {
  final _reverse = <String, CachedReverseGeocode>{};
  final _resolved = <String, CachedResolvedPlace>{};

  @override
  Future<CachedReverseGeocode?> readReverseGeocode(String key) async =>
      _reverse[key];

  @override
  Future<void> writeReverseGeocode(
    String key,
    ReverseGeocodeResult result,
  ) async {
    _reverse[key] = CachedReverseGeocode(result: result, isFresh: true);
  }

  @override
  Future<CachedResolvedPlace?> readResolvedPlace(String key) async =>
      _resolved[key];

  @override
  Future<void> writeResolvedPlace(String key, ResolvedPlace place) async {
    _resolved[key] = CachedResolvedPlace(place: place, isFresh: true);
  }

  /// Test helper: seeds a stale entry, as if it were written a week ago.
  void seedStaleReverseGeocode(String key, ReverseGeocodeResult result) {
    _reverse[key] = CachedReverseGeocode(result: result, isFresh: false);
  }

  void seedStaleResolvedPlace(String key, ResolvedPlace place) {
    _resolved[key] = CachedResolvedPlace(place: place, isFresh: false);
  }
}

/// Fake network transport the tests drive directly, without going through
/// [ApiClient]/`http.testing.MockClient` — this exercises [MapsRepository]'s
/// cache/offline logic in isolation from HTTP wire details, which the
/// `MapsApi` tests already cover.
class _FakeMapsApi implements MapsApi {
  ReverseGeocodeResult Function(LatLng)? reverseGeocodeAnswer;
  Object? reverseGeocodeError;

  ResolvedPlace Function(String)? resolveUrlAnswer;
  Object? resolveUrlError;

  @override
  Future<ReverseGeocodeResult> reverseGeocode(LatLng point) async {
    if (reverseGeocodeError != null) throw reverseGeocodeError!;
    return reverseGeocodeAnswer!(point);
  }

  @override
  Future<ResolvedPlace> resolveUrl(String url) async {
    if (resolveUrlError != null) throw resolveUrlError!;
    return resolveUrlAnswer!(url);
  }
}

void main() {
  late _FakeMapsApi api;
  late _InMemoryMapsLocalStore localStore;
  late MapsRepository repository;

  setUp(() {
    api = _FakeMapsApi();
    localStore = _InMemoryMapsLocalStore();
    repository = MapsRepository(mapsApi: api, localStore: localStore);
  });

  group('reverseGeocode', () {
    const point = LatLng(48.8566, 2.3522);

    test('fetches and caches on a cold lookup', () async {
      api.reverseGeocodeAnswer = (_) =>
          const ReverseGeocodeResult(name: 'Notre-Dame', address: 'Paris');

      final snapshot = await repository.reverseGeocode(point);

      expect(snapshot.result.name, 'Notre-Dame');
      expect(snapshot.fromCache, isFalse);
      expect(snapshot.stale, isFalse);
      expect(
        (await localStore.readReverseGeocode(point.cacheKey))!.isFresh,
        isTrue,
      );
    });

    test(
      'a fresh cache entry is returned without calling the network',
      () async {
        await localStore.writeReverseGeocode(
          point.cacheKey,
          const ReverseGeocodeResult(name: 'Cached answer'),
        );
        api.reverseGeocodeAnswer = (_) =>
            throw StateError('should not call the network');

        final snapshot = await repository.reverseGeocode(point);

        expect(snapshot.result.name, 'Cached answer');
        expect(snapshot.fromCache, isTrue);
        expect(snapshot.stale, isFalse);
      },
    );

    test(
      'falls back to a stale cached answer when the network throws',
      () async {
        localStore.seedStaleReverseGeocode(
          point.cacheKey,
          const ReverseGeocodeResult(name: 'Last known answer'),
        );
        api.reverseGeocodeError = const NetworkException();

        final snapshot = await repository.reverseGeocode(point);

        expect(snapshot.result.name, 'Last known answer');
        expect(snapshot.fromCache, isTrue);
        expect(snapshot.stale, isTrue);
      },
    );

    test(
      'propagates NetworkException when nothing is cached (offline, first run)',
      () async {
        api.reverseGeocodeError = const NetworkException();

        expect(
          () => repository.reverseGeocode(point),
          throwsA(isA<NetworkException>()),
        );
      },
    );

    test(
      'treats an all-null geocoder answer as a miss, falling back to a stale cache entry',
      () async {
        localStore.seedStaleReverseGeocode(
          point.cacheKey,
          const ReverseGeocodeResult(name: 'Old answer'),
        );
        api.reverseGeocodeAnswer = (_) => const ReverseGeocodeResult();

        final snapshot = await repository.reverseGeocode(point);

        expect(snapshot.result.name, 'Old answer');
        expect(snapshot.stale, isTrue);
      },
    );

    test('forceRefresh bypasses a fresh cache entry', () async {
      await localStore.writeReverseGeocode(
        point.cacheKey,
        const ReverseGeocodeResult(name: 'Old'),
      );
      api.reverseGeocodeAnswer = (_) =>
          const ReverseGeocodeResult(name: 'Refreshed');

      final snapshot = await repository.reverseGeocode(
        point,
        forceRefresh: true,
      );

      expect(snapshot.result.name, 'Refreshed');
      expect(snapshot.fromCache, isFalse);
    });
  });

  group('resolveUrl', () {
    const url = 'https://maps.app.goo.gl/abc123';

    test('fetches and caches on a cold lookup', () async {
      api.resolveUrlAnswer = (_) =>
          const ResolvedPlace(point: LatLng(1, 2), name: 'A place');

      final snapshot = await repository.resolveUrl(url);

      expect(snapshot.place.name, 'A place');
      expect(snapshot.fromCache, isFalse);
    });

    test(
      'a fresh cache entry is returned without calling the network',
      () async {
        await localStore.writeResolvedPlace(
          url,
          const ResolvedPlace(point: LatLng(1, 2), name: 'Cached place'),
        );
        api.resolveUrlAnswer = (_) =>
            throw StateError('should not call the network');

        final snapshot = await repository.resolveUrl(url);

        expect(snapshot.place.name, 'Cached place');
        expect(snapshot.fromCache, isTrue);
      },
    );

    test(
      'falls back to a stale cached answer when the network throws',
      () async {
        localStore.seedStaleResolvedPlace(
          url,
          const ResolvedPlace(point: LatLng(1, 2), name: 'Last known place'),
        );
        api.resolveUrlError = const NetworkException();

        final snapshot = await repository.resolveUrl(url);

        expect(snapshot.place.name, 'Last known place');
        expect(snapshot.stale, isTrue);
      },
    );

    test(
      'propagates NetworkException when nothing is cached (offline, first run)',
      () async {
        api.resolveUrlError = const NetworkException();

        expect(
          () => repository.resolveUrl(url),
          throwsA(isA<NetworkException>()),
        );
      },
    );

    test(
      'a ValidationException (URL does not resolve) always propagates, even with a stale cache entry',
      () async {
        localStore.seedStaleResolvedPlace(
          url,
          const ResolvedPlace(point: LatLng(1, 2), name: 'Old place'),
        );
        api.resolveUrlError = const ValidationException(
          'Failed to resolve URL',
        );

        expect(
          () => repository.resolveUrl(url),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('URLs are trimmed before use as a cache key', () async {
      api.resolveUrlAnswer = (received) {
        expect(received, url);
        return const ResolvedPlace(point: LatLng(1, 2), name: 'A place');
      };

      await repository.resolveUrl('  $url  ');

      expect(await localStore.readResolvedPlace(url), isNotNull);
    });
  });
}
