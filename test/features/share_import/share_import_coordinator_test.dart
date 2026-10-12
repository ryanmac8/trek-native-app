import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/trek_app.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/auth/session_token.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/share_import/share_import_store.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/share_intake/shared_map_link.dart';

import '../../test_helpers.dart';

const _server = 'https://trek.example.com';

/// End-to-end through [TrekApp]: the OS share → coordinator → router →
/// share screen, and the startup flush of queued imports.
void main() {
  late FakeShareIntake intake;
  late InMemoryShareImportStore store;
  late List<String> requests;

  setUp(() {
    intake = FakeShareIntake();
    store = InMemoryShareImportStore();
    requests = [];
  });

  Future<void> pumpApp(WidgetTester tester, {required bool signedIn}) async {
    final tokenStorage = InMemoryTokenStorage();
    if (signedIn) {
      final exp =
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000;
      await tokenStorage.write(
        SessionToken.fromJwt(fakeJwt({'id': 1, 'exp': exp})),
      );
    }
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      final body = switch (request.url.path) {
        '/api/trips' => {'trips': <Object>[]},
        '/api/maps/resolve-url' => {
          'lat': 1.0,
          'lng': 2.0,
          'name': 'Resolved',
          'address': null,
        },
        _ => {
          'place': {'id': 1},
        },
      };
      return http.Response(jsonEncode(body), 200);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(
              initial: const ServerConfig(publicUrl: _server),
            ),
          ),
          authServiceProvider.overrideWithValue(
            AuthService(
              apiClient: ApiClient(baseUrl: _server),
              tokenStorage: tokenStorage,
            ),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: _server, httpClient: client),
          ),
          shareIntakeProvider.overrideWithValue(intake),
          shareImportStoreProvider.overrideWithValue(store),
        ],
        child: const TrekApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a share that launched the app opens the share screen', (
    tester,
  ) async {
    intake.initial = 'Sky Tower\nhttps://maps.app.goo.gl/abc';

    await pumpApp(tester, signedIn: true);

    expect(find.text('Add to a trip'), findsOneWidget);
  });

  testWidgets('a share while running opens the share screen', (tester) async {
    await pumpApp(tester, signedIn: true);
    expect(find.text('Trips'), findsOneWidget);

    intake.share('https://maps.apple.com/?ll=1.0,2.0&q=Pin');
    await tester.pumpAndSettle();

    expect(find.text('Add to a trip'), findsOneWidget);
    expect(find.text('Apple Maps link'), findsOneWidget);
  });

  testWidgets('a share without a map link explains and stays put', (
    tester,
  ) async {
    await pumpApp(tester, signedIn: true);

    intake.share('https://example.com/not-a-map');
    await tester.pumpAndSettle();

    expect(find.textContaining('No map link was found'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('signed out: a cold-start share waits for login', (tester) async {
    intake.initial = 'https://maps.app.goo.gl/abc';

    await pumpApp(tester, signedIn: false);

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Add to a trip'), findsNothing);
  });

  testWidgets('queued imports are sent at startup when signed in', (
    tester,
  ) async {
    store.pending = [
      const PendingPlaceImport(
        id: 'q1',
        serverUrl: _server,
        tripId: 20,
        tripTitle: 'New Zealand',
        url: 'https://maps.app.goo.gl/abc',
        provider: MapLinkProvider.google,
      ),
    ];

    await pumpApp(tester, signedIn: true);

    expect(requests, contains('POST /api/trips/20/places'));
    expect(store.pending, isEmpty);
    expect(find.text('Added "Resolved" to your trip.'), findsOneWidget);
  });

  testWidgets('queued imports are not sent while signed out', (tester) async {
    store.pending = [
      const PendingPlaceImport(
        id: 'q1',
        serverUrl: _server,
        tripId: 20,
        tripTitle: 'New Zealand',
        url: 'https://maps.app.goo.gl/abc',
        provider: MapLinkProvider.google,
      ),
    ];

    await pumpApp(tester, signedIn: false);

    expect(requests, isEmpty);
    expect(store.pending, hasLength(1));
  });
}
