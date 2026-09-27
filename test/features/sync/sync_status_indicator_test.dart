import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/app_messenger.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/features/sync/sync_status_indicator.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/sync/pending_write.dart';
import 'package:trek/sync/sync_engine.dart';
import 'package:trek/sync/sync_status.dart';

import '../../test_helpers.dart';

class ScriptedHandler extends SyncHandler {
  final pushed = <PendingWrite>[];
  Object? error;

  @override
  Future<void> push(PendingWrite write) async {
    pushed.add(write);
    if (error != null) throw error!;
  }
}

PendingWrite queued(String id) => PendingWrite(
  id: id,
  kind: 'todo.update',
  payload: {'id': id},
  createdAt: DateTime.utc(2026, 9, 27),
);

void main() {
  late ScriptedHandler handler;
  late AuthService authService;
  late ProviderContainer container;

  Future<void> pumpIndicator(
    WidgetTester tester, {
    List<PendingWrite> pending = const [],
  }) async {
    handler = ScriptedHandler();
    authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        outboxStoreProvider.overrideWithValue(InMemoryOutboxStore(pending)),
        syncHandlersProvider.overrideWithValue({'todo.update': handler}),
      ],
    );
    // Disposing the engine cancels any pending retry timer, which the test
    // binding would otherwise report as leaked.
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: Scaffold(
            appBar: AppBar(actions: const [SyncStatusIndicator()]),
          ),
        ),
      ),
    );
  }

  testWidgets('is hidden when nothing is queued', (tester) async {
    await pumpIndicator(tester);
    await container.read(syncEngineProvider).start();
    await tester.pump();

    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('shows the offline state with a pending-count badge, and '
      'retries when tapped', (tester) async {
    await pumpIndicator(tester, pending: [queued('1'), queued('2')]);
    handler.error = const NetworkException();

    await container.read(syncEngineProvider).start();
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.byTooltip('Offline — 2 changes will sync when reconnected.'),
      findsOneWidget,
    );

    handler.error = null;
    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(
      find.text('Offline — 2 changes will sync when reconnected.'),
      findsOneWidget,
      reason: 'tapping explains the state it was in',
    );
    expect(handler.pushed.map((w) => w.id), ['1', '1', '2']);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('logging in drains writes held back by a 401', (tester) async {
    await pumpIndicator(tester, pending: [queued('1')]);
    handler.error = const UnauthorizedException();

    await container.read(syncEngineProvider).start();
    await tester.pump();
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);

    handler.error = null;
    authService.isAuthenticated.value = true;
    await tester.pump();
    await tester.pump();

    expect(handler.pushed, hasLength(2));
    expect(find.byType(IconButton), findsNothing);
  });

  group('describeSyncStatus', () {
    test('describes each phase with a pluralized count', () {
      expect(
        describeSyncStatus(
          const SyncStatus(phase: SyncPhase.syncing, pendingCount: 1),
        ),
        'Syncing 1 change…',
      );
      expect(
        describeSyncStatus(
          const SyncStatus(phase: SyncPhase.retrying, pendingCount: 3),
        ),
        'Server error — retrying 3 changes shortly.',
      );
      expect(
        describeSyncStatus(
          const SyncStatus(phase: SyncPhase.authRequired, pendingCount: 2),
        ),
        'Log in again to sync 2 changes.',
      );
      expect(
        describeSyncStatus(const SyncStatus(pendingCount: 4)),
        '4 changes waiting to sync.',
      );
    });
  });
}
