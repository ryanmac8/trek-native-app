import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/home_widgets/home_widget_refresher.dart';
import 'package:trek/home_widgets/next_trip_widget_sync.dart';
import 'package:trek/home_widgets/widget_trip_api.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

class _CountingSync extends NextTripWidgetSync {
  _CountingSync()
    : super(
        api: WidgetTripApi(
          apiClient: ApiClient(baseUrl: 'https://unused.example.com'),
        ),
        store: InMemoryWidgetTripStore(),
        publisher: RecordingHomeWidgetPublisher(),
        cacheScope: () async => null,
      );

  int refreshes = 0;
  int clears = 0;
  bool throwOnRefresh = false;

  @override
  Future<NextTripWidgetSyncResult> refresh() async {
    refreshes++;
    if (throwOnRefresh) throw StateError('boom');
    return NextTripWidgetSyncResult.fresh;
  }

  @override
  Future<void> clear() async => clears++;
}

void main() {
  late AuthService authService;
  late _CountingSync sync;

  setUp(() {
    authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://unused.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    sync = _CountingSync();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        nextTripWidgetSyncProvider.overrideWithValue(sync),
      ],
      child: const HomeWidgetRefresher(child: SizedBox()),
    ),
  );

  testWidgets('refreshes on mount with a live session', (tester) async {
    authService.isAuthenticated.value = true;
    await pump(tester);

    expect(sync.refreshes, 1);
  });

  testWidgets('does nothing on mount while signed out', (tester) async {
    await pump(tester);

    expect(sync.refreshes, 0);
    expect(sync.clears, 0);
  });

  testWidgets('refreshes on sign-in and clears on sign-out', (tester) async {
    await pump(tester);

    authService.isAuthenticated.value = true;
    expect(sync.refreshes, 1);

    authService.isAuthenticated.value = false;
    expect(sync.clears, 1);
  });

  testWidgets('refreshes when the app returns to the foreground', (
    tester,
  ) async {
    authService.isAuthenticated.value = true;
    await pump(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(sync.refreshes, 2);
  });

  testWidgets('swallows a failing refresh', (tester) async {
    sync.throwOnRefresh = true;
    authService.isAuthenticated.value = true;
    await pump(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(sync.refreshes, 1);
  });
}
