import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/splash_screen.dart';

void main() {
  testWidgets('shows the T-mark and tagline, fully revealed once animated', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Your Trips.\nYour Plan.'), findsOneWidget);

    final logoFade = find.byKey(const ValueKey('splash-logo-fade'));

    // Mid-animation: not fully revealed yet.
    await tester.pump(const Duration(milliseconds: 100));
    final midOpacity = tester.widget<FadeTransition>(logoFade).opacity.value;
    expect(midOpacity, lessThan(1.0));

    // Reveal animation (900ms) complete.
    await tester.pump(const Duration(milliseconds: 900));
    final doneOpacity = tester.widget<FadeTransition>(logoFade).opacity.value;
    expect(doneOpacity, 1.0);
  });

  testWidgets('disposes its animation controllers cleanly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    // No exception thrown by leaked/still-running tickers — pumpAndSettle
    // above would hang or flutter_test's leak checker would flag it.
  });
}
