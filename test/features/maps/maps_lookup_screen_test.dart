import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/maps/maps_lookup_screen.dart';
import 'package:trek/maps/maps_api.dart';
import 'package:trek/maps/maps_local_store.dart';
import 'package:trek/maps/maps_models.dart';
import 'package:trek/maps/maps_repository.dart';
import 'package:trek/network/api_exception.dart';

/// In-memory [MapsLocalStore] fake so the widget test doesn't touch the
/// shared_preferences platform channel.
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
}

class _FakeMapsApi implements MapsApi {
  Object? reverseGeocodeError;
  Object? resolveUrlError;
  ResolvedPlace? resolvedPlace;

  @override
  Future<ReverseGeocodeResult> reverseGeocode(LatLng point) async {
    if (reverseGeocodeError != null) throw reverseGeocodeError!;
    return const ReverseGeocodeResult(
      name: 'Eiffel Tower',
      address: 'Paris, France',
    );
  }

  @override
  Future<ResolvedPlace> resolveUrl(String url) async {
    if (resolveUrlError != null) throw resolveUrlError!;
    return resolvedPlace!;
  }
}

void main() {
  late _FakeMapsApi api;
  late MapsRepository repository;

  setUp(() {
    api = _FakeMapsApi();
    repository = MapsRepository(
      mapsApi: api,
      localStore: _InMemoryMapsLocalStore(),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: MapsLookupScreen()),
      ),
    );
  }

  testWidgets('resolves a pasted Maps URL and shows the place', (tester) async {
    api.resolvedPlace = const ResolvedPlace(
      point: LatLng(48.8584, 2.2945),
      name: 'Eiffel Tower',
      address: 'Paris, France',
    );
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'https://maps.app.goo.gl/...'),
      'https://maps.app.goo.gl/abc123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Eiffel Tower'), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
  });

  testWidgets('reverse-geocodes a coordinate typed into the lat/lng fields', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Latitude'),
      '48.8566',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Longitude'),
      '2.3522',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Look up'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Eiffel Tower'), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
  });

  testWidgets('shows an inline error for an out-of-range coordinate', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Latitude'), '200');
    await tester.enterText(
      find.widgetWithText(TextField, 'Longitude'),
      '2.3522',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Look up'));
    await tester.pump();

    expect(find.text('Enter a valid latitude and longitude.'), findsOneWidget);
  });

  testWidgets(
    'shows the offline error message when resolving a URL fails offline with nothing cached',
    (tester) async {
      api.resolveUrlError = const NetworkException();
      await pump(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'https://maps.app.goo.gl/...'),
        'https://maps.app.goo.gl/abc123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Unable to reach the server.'), findsOneWidget);
    },
  );
}
