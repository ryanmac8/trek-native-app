import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/permissions/app_permission.dart';
import 'package:trek/permissions/permission_gateway.dart';
import 'package:trek/permissions/permission_primer.dart';

import '../test_helpers.dart';

const _location = AppPermission.location;

void main() {
  late FakePermissionGateway gateway;
  late InMemoryPrimingStorage storage;
  late DateTime now;
  late PermissionPrimer primer;

  setUp(() {
    gateway = FakePermissionGateway();
    storage = InMemoryPrimingStorage();
    now = DateTime.utc(2026, 10, 11, 12);
    primer = PermissionPrimer(
      gateway: gateway,
      storage: storage,
      clock: () => now,
    );
  });

  /// Outcome of the most recent [startEnsure], once `ensure` resolves.
  PrimingOutcome? outcome;

  /// Pumps a button that runs [PermissionPrimer.ensure], taps it, and
  /// settles. The result lands in [outcome] — read it rather than awaiting
  /// the future, which would block the test's fake-async zone.
  Future<void> startEnsure(
    WidgetTester tester, {
    bool userInitiated = false,
  }) async {
    outcome = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => primer
                  .ensure(context, _location, userInitiated: userInitiated)
                  .then((result) => outcome = result),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('already granted: no sheet, no OS prompt', (tester) async {
    gateway.statuses[_location] = AppPermissionStatus.granted;

    await startEnsure(tester);

    expect(find.text(_location.title), findsNothing);
    expect(outcome, PrimingOutcome.granted);
    expect(gateway.requested, isEmpty);
  });

  testWidgets('shows the priming sheet before the OS prompt', (tester) async {
    gateway.requestResults[_location] = AppPermissionStatus.granted;

    await startEnsure(tester);

    expect(find.text(_location.title), findsOneWidget);
    expect(find.text(_location.rationale), findsOneWidget);
    expect(gateway.requested, isEmpty);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(outcome, PrimingOutcome.granted);
    expect(gateway.requested, [_location]);
  });

  testWidgets('granting clears an earlier "Not now"', (tester) async {
    storage.declines[_location] = now.subtract(const Duration(days: 30));
    gateway.requestResults[_location] = AppPermissionStatus.granted;

    await startEnsure(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(outcome, PrimingOutcome.granted);
    expect(storage.declines, isEmpty);
  });

  testWidgets('refusing the OS prompt reports denied', (tester) async {
    gateway.requestResults[_location] = AppPermissionStatus.denied;

    await startEnsure(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(outcome, PrimingOutcome.denied);
  });

  testWidgets('"don\'t ask again" at the OS prompt reports blocked', (
    tester,
  ) async {
    gateway.requestResults[_location] = AppPermissionStatus.permanentlyDenied;

    await startEnsure(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(outcome, PrimingOutcome.blocked);
  });

  testWidgets('"Not now" skips the OS prompt and records the decline', (
    tester,
  ) async {
    await startEnsure(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(outcome, PrimingOutcome.dismissed);
    expect(gateway.requested, isEmpty);
    expect(storage.declines[_location], now);
  });

  testWidgets('swiping the sheet away counts as "Not now"', (tester) async {
    await startEnsure(tester);
    await tester.tapAt(const Offset(10, 10)); // the modal barrier
    await tester.pumpAndSettle();

    expect(outcome, PrimingOutcome.dismissed);
    expect(gateway.requested, isEmpty);
    expect(storage.declines[_location], now);
  });

  group('cooldown after "Not now"', () {
    testWidgets('automatic prime within the cooldown is snoozed', (
      tester,
    ) async {
      storage.declines[_location] = now.subtract(const Duration(days: 13));

      await startEnsure(tester);

      expect(find.text(_location.title), findsNothing);
      expect(outcome, PrimingOutcome.snoozed);
    });

    testWidgets('automatic prime after the cooldown shows the sheet', (
      tester,
    ) async {
      storage.declines[_location] = now.subtract(const Duration(days: 15));

      await startEnsure(tester);

      expect(find.text(_location.title), findsOneWidget);
    });

    testWidgets('user-initiated prime ignores the cooldown', (tester) async {
      storage.declines[_location] = now.subtract(const Duration(hours: 1));

      await startEnsure(tester, userInitiated: true);

      expect(find.text(_location.title), findsOneWidget);
    });
  });

  group('blocked by the OS', () {
    testWidgets('automatic prime returns blocked with no UI', (tester) async {
      gateway.statuses[_location] = AppPermissionStatus.permanentlyDenied;

      await startEnsure(tester);

      expect(find.text(_location.blockedMessage), findsNothing);
      expect(outcome, PrimingOutcome.blocked);
      expect(gateway.requested, isEmpty);
    });

    testWidgets('user-initiated prime offers Settings', (tester) async {
      gateway.statuses[_location] = AppPermissionStatus.permanentlyDenied;

      await startEnsure(tester, userInitiated: true);

      expect(find.text(_location.blockedMessage), findsOneWidget);
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(outcome, PrimingOutcome.blocked);
      expect(gateway.openSettingsCalls, 1);
      expect(gateway.requested, isEmpty);
    });

    testWidgets('dismissing the Settings sheet does not open Settings', (
      tester,
    ) async {
      gateway.statuses[_location] = AppPermissionStatus.permanentlyDenied;

      await startEnsure(tester, userInitiated: true);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(outcome, PrimingOutcome.blocked);
      expect(gateway.openSettingsCalls, 0);
    });

    testWidgets('restricted offers no Settings button', (tester) async {
      gateway.statuses[_location] = AppPermissionStatus.restricted;

      await startEnsure(tester, userInitiated: true);

      expect(find.text('Open Settings'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(outcome, PrimingOutcome.blocked);
      expect(gateway.openSettingsCalls, 0);
    });
  });
}
