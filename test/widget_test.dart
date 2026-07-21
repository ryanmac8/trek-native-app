import 'package:flutter_test/flutter_test.dart';

import 'package:trek/main.dart';

void main() {
  testWidgets('renders home page', (WidgetTester tester) async {
    await tester.pumpWidget(const TrekApp());

    expect(find.text('Trek'), findsOneWidget);
  });
}
