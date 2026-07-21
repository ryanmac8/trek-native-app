import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/widgets/app_card.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('Card content'))),
      ),
    );

    expect(find.text('Card content'), findsOneWidget);
  });

  testWidgets('is not tappable without onTap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('Static'))),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('calls onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(
            onTap: () => tapped = true,
            child: const Text('Tappable'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppCard));
    expect(tapped, isTrue);
  });
}
