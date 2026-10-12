import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_messenger.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/router.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/share_import/share_import_api.dart';
import 'package:trek/features/share_import/share_import_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/share_intake/shared_map_link.dart';

import '../../test_helpers.dart';

const _server = 'https://trek.example.com';

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late bool offline;
  late List<Map<String, dynamic>> createBodies;
  late http.Response Function() createResponse;
  late InMemoryShareImportStore store;
  late ValueNotifier<SharedMapLink?> incoming;

  setUp(() {
    offline = false;
    createBodies = [];
    createResponse = () => _json(201, {
      'place': {'id': 7},
    });
    store = InMemoryShareImportStore();
    incoming = ValueNotifier(
      SharedMapLink.parse('Sky Tower\nhttps://maps.app.goo.gl/abc'),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    final client = MockClient((request) async {
      if (offline) throw const SocketException('offline');
      switch (request.url.path) {
        case '/api/trips':
          return _json(200, {
            'trips': [
              {
                'id': 20,
                'title': 'New Zealand',
                'start_date': '2026-11-01',
                'end_date': '2026-11-14',
              },
              {'id': 21, 'title': 'Someday', 'start_date': null},
            ],
          });
        case '/api/maps/resolve-url':
          return _json(200, {
            'lat': -36.8485,
            'lng': 174.7622,
            'name': 'Sky Tower',
            'address': 'Auckland',
          });
        default:
          createBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return createResponse();
      }
    });
    final authService = AuthService(
      apiClient: ApiClient(baseUrl: _server),
      tokenStorage: InMemoryTokenStorage(),
    )..isAuthenticated.value = true;
    final serverConfig = InMemoryServerConfigStorage(
      initial: const ServerConfig(publicUrl: _server),
    );
    final repository = ShareImportRepository(
      api: ShareImportApi(
        apiClient: ApiClient(baseUrl: _server, httpClient: client),
      ),
      store: store,
      currentServer: () async => _server,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingShareProvider.overrideWithValue(incoming),
          shareImportRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: buildAppRouter(
            authService: authService,
            serverConfigStorage: serverConfig,
            incomingShare: incoming,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('online: pick a trip and add the place', (tester) async {
    await pump(tester);

    expect(find.text('Add to a trip'), findsOneWidget);
    expect(find.text('Google Maps link'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Sky Tower'), findsOneWidget);
    expect(find.text('2026-11-01 – 2026-11-14'), findsOneWidget);

    await tester.tap(find.text('New Zealand'));
    await tester.pump();
    await tester.tap(find.text('Add to place pool'));
    await tester.pumpAndSettle();

    expect(createBodies.single['name'], 'Sky Tower');
    expect(find.text('Added "Sky Tower" to New Zealand.'), findsOneWidget);
    expect(incoming.value, isNull);
    // The router moved on to the trip list.
    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('the add button is disabled until a trip is picked', (
    tester,
  ) async {
    await pump(tester);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('offline with cached trips: picks from cache, queues import', (
    tester,
  ) async {
    store.trips[_server] = const [
      ShareTargetTrip(id: 20, title: 'New Zealand'),
    ];
    offline = true;

    await pump(tester);

    expect(find.textContaining('You\'re offline — showing trips'), findsOne);
    await tester.tap(find.text('New Zealand'));
    await tester.pump();
    await tester.tap(find.text('Add to place pool'));
    await tester.pumpAndSettle();

    expect(store.pending.single.tripId, 20);
    expect(store.pending.single.suggestedName, 'Sky Tower');
    expect(
      find.textContaining('will be added to New Zealand when you\'re back'),
      findsOneWidget,
    );
    expect(incoming.value, isNull);
  });

  testWidgets('offline with nothing cached: explicit offline state, retry', (
    tester,
  ) async {
    offline = true;

    await pump(tester);

    expect(
      find.textContaining('your trips haven\'t been loaded on this device'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    offline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('New Zealand'), findsOneWidget);
  });

  testWidgets('a refused import stays on the screen with the error', (
    tester,
  ) async {
    createResponse = () => _json(403, {'error': 'No permission'});

    await pump(tester);
    await tester.tap(find.text('New Zealand'));
    await tester.pump();
    await tester.tap(find.text('Add to place pool'));
    await tester.pumpAndSettle();

    expect(find.text('No permission'), findsOneWidget);
    expect(find.text('Add to a trip'), findsOneWidget);
    expect(incoming.value, isNotNull);
    expect(store.pending, isEmpty);
  });

  testWidgets('Cancel dismisses the share', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(incoming.value, isNull);
    expect(find.text('Trips'), findsOneWidget);
    expect(createBodies, isEmpty);
  });
}
