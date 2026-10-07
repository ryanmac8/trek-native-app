import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/addons/addon_flags.dart';
import 'package:trek/addons/addon_flags_controller.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/design/place_category_colors.dart';
import 'package:trek/features/trips/trip_dashboard_screen.dart';

import '../../addons/addon_fixtures.dart';

/// Holds a fixed [AddonFlagsState] — no repository, no network.
class _FixedAddonFlags extends AddonFlagsController {
  _FixedAddonFlags(this._initial) : super((_) => throw UnimplementedError());

  final AddonFlagsState _initial;

  @override
  AddonFlagsState build() => _initial;

  void set(AddonFlagsState next) => state = next;
}

AddonFlagsState _serverFlags(Map<String, dynamic> body) => AddonFlagsState(
  flags: AddonFlags.fromJson(body),
  source: AddonFlagsSource.server,
);

void main() {
  late _FixedAddonFlags controller;

  Future<void> pumpDashboard(
    WidgetTester tester, [
    AddonFlagsState state = AddonFlagsState.initial,
  ]) async {
    controller = _FixedAddonFlags(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [addonFlagsProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: TripDashboardScreen(tripId: 'trip-1')),
      ),
    );
  }

  testWidgets('shows the trip id and all five section tabs', (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Trip trip-1'), findsOneWidget);
    for (final label in ['Days', 'Places', 'Budget', 'Packing', 'Todos']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('switching tabs shows the corresponding placeholder', (
    tester,
  ) async {
    await pumpDashboard(tester);
    expect(find.text('Days — coming soon'), findsOneWidget);

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();

    expect(find.text('Budget — coming soon'), findsOneWidget);
    expect(find.text('Days — coming soon'), findsNothing);
  });

  testWidgets('Places tab previews every default category color/icon', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();

    for (final category in PlaceCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
  });

  testWidgets('hides Budget when the budget add-on is off', (tester) async {
    await pumpDashboard(tester, _serverFlags(addonsResponse(budget: false)));

    expect(find.text('Budget'), findsNothing);
    expect(find.text('Packing'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
  });

  testWidgets('hides Packing and Todos when the Lists add-on is off', (
    tester,
  ) async {
    await pumpDashboard(tester, _serverFlags(addonsResponse(packing: false)));

    expect(find.text('Packing'), findsNothing);
    expect(find.text('Todos'), findsNothing);
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Places'), findsOneWidget);
  });

  testWidgets('falls back to Days when the selected tab is switched off', (
    tester,
  ) async {
    await pumpDashboard(tester, _serverFlags(addonsResponse()));
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    expect(find.text('Todos — coming soon'), findsOneWidget);

    controller.set(_serverFlags(addonsResponse(packing: false)));
    await tester.pumpAndSettle();

    expect(find.text('Todos'), findsNothing);
    expect(find.text('Days — coming soon'), findsOneWidget);
  });

  testWidgets('keeps the selected tab when other tabs appear or vanish', (
    tester,
  ) async {
    await pumpDashboard(tester, _serverFlags(addonsResponse()));
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();

    controller.set(_serverFlags(addonsResponse(budget: false)));
    await tester.pumpAndSettle();

    expect(find.text('Todos — coming soon'), findsOneWidget);
  });
}
