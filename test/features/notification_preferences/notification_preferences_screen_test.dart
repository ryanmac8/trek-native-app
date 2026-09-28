import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/notification_preferences/notification_preferences_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/notification_preferences/notification_preferences_api.dart';
import 'package:trek/notification_preferences/notification_preferences_local_store.dart';
import 'package:trek/notification_preferences/notification_preferences_models.dart';
import 'package:trek/notification_preferences/notification_preferences_repository.dart';

import '../../notification_preferences/notification_preferences_fixtures.dart';

class _InMemoryLocalStore implements NotificationPreferencesLocalStore {
  final _entries = <String, CachedNotificationPreferences>{};

  @override
  Future<CachedNotificationPreferences?> read(String scope) async =>
      _entries[scope];

  @override
  Future<void> write(String scope, CachedNotificationPreferences value) async =>
      _entries[scope] = value;
}

void main() {
  late FakePreferencesServer server;
  late _InMemoryLocalStore store;

  setUp(() {
    server = FakePreferencesServer();
    store = _InMemoryLocalStore();
  });

  NotificationPreferencesRepository buildRepository() =>
      NotificationPreferencesRepository(
        api: NotificationPreferencesApi(
          apiClient: ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: server.client,
          ),
        ),
        localStore: store,
        cacheScope: () async => 'scope',
        clock: () => DateTime(2026, 9, 27, 18, 5),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPreferencesRepositoryProvider.overrideWithValue(
            buildRepository(),
          ),
        ],
        child: const MaterialApp(home: NotificationPreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

  testWidgets('renders one card per event with its visible channels', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Trip invitations'), findsOneWidget);
    expect(find.text('Synology session cleared'), findsOneWidget);
    // Four visible channels × three events + in-app only for the fourth.
    expect(find.byType(SwitchListTile), findsNWidgets(13));
    // ntfy is switched off by the admin, so it never appears.
    expect(find.text('Ntfy'), findsNothing);
    expect(find.text('Matrix chat'), findsNWidgets(3));
    // Webhook is active but this user hasn't configured it.
    expect(find.text('Not configured yet'), findsNWidgets(3));
  });

  testWidgets('a toggle is saved to the server', (tester) async {
    await pumpScreen(tester);
    expect(switchValue(tester, 'pref-trip_invite-email'), isTrue);

    await tester.tap(find.byKey(const Key('pref-trip_invite-email')));
    await tester.pumpAndSettle();

    expect(switchValue(tester, 'pref-trip_invite-email'), isFalse);
    expect(server.stored['trip_invite']!['email'], isFalse);
    expect(find.textContaining('waiting to sync'), findsNothing);
  });

  group('offline', () {
    testWidgets('a toggle applies locally and shows as pending', (
      tester,
    ) async {
      await pumpScreen(tester);
      server.offline = true;

      await tester.tap(find.byKey(const Key('pref-booking_change-inapp')));
      await tester.pumpAndSettle();

      expect(switchValue(tester, 'pref-booking_change-inapp'), isFalse);
      expect(
        find.text(
          '1 change saved on this device, waiting to sync with your '
          'server.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Offline — showing preferences'), findsOne);
      expect(server.stored, isEmpty);

      // Back online: a retry syncs the pending change.
      server.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(server.stored['booking_change']!['inapp'], isFalse);
      expect(find.textContaining('waiting to sync'), findsNothing);
      expect(switchValue(tester, 'pref-booking_change-inapp'), isFalse);
    });

    testWidgets('shows the cached matrix with an offline banner', (
      tester,
    ) async {
      await buildRepository().refresh();
      server.offline = true;

      await pumpScreen(tester);

      expect(find.text('Trip invitations'), findsOneWidget);
      expect(
        find.text('Offline — showing preferences from 2026-09-27 18:05.'),
        findsOneWidget,
      );
    });

    testWidgets('with nothing cached shows an offline state with retry', (
      tester,
    ) async {
      server.offline = true;

      await pumpScreen(tester);

      expect(
        find.text(
          "You're offline, and your notification preferences haven't been "
          'loaded yet.',
        ),
        findsOneWidget,
      );

      server.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Trip invitations'), findsOneWidget);
    });
  });

  testWidgets('a rejected toggle reverts to the server value', (tester) async {
    await pumpScreen(tester);
    server.putStatus = 400;

    await tester.tap(find.byKey(const Key('pref-collab_message-inapp')));
    await tester.pumpAndSettle();

    expect(switchValue(tester, 'pref-collab_message-inapp'), isTrue);
    expect(find.textContaining('waiting to sync'), findsNothing);
  });
}
