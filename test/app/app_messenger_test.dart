import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/app_messenger.dart';
import 'package:trek/design/app_colors.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
  }

  testWidgets('showError displays the message in a danger-colored snackbar', (
    tester,
  ) async {
    await pumpApp(tester);

    AppMessenger.showError('Something went wrong.');
    await tester.pump();

    expect(find.text('Something went wrong.'), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, AppColors.danger);
  });

  testWidgets(
    'showSuccess displays the message in a success-colored snackbar',
    (tester) async {
      await pumpApp(tester);

      AppMessenger.showSuccess('Saved.');
      await tester.pump();

      expect(find.text('Saved.'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, AppColors.success);
    },
  );

  testWidgets('a second message replaces the first rather than stacking', (
    tester,
  ) async {
    await pumpApp(tester);

    AppMessenger.showInfo('First.');
    await tester.pump();
    AppMessenger.showInfo('Second.');
    await tester.pump();

    expect(find.text('First.'), findsNothing);
    expect(find.text('Second.'), findsOneWidget);
  });

  testWidgets('does nothing (no throw) when no messenger is mounted', (
    tester,
  ) async {
    // Ensure the key isn't attached to anything from a previous test.
    await tester.pumpWidget(const SizedBox());

    expect(() => AppMessenger.showError('Unmounted.'), returnsNormally);
  });
}
