import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/widgets/app_list_row.dart';

void main() {
  testWidgets('renders title, optional subtitle, leading, and trailing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppListRow(
            title: 'Paris',
            subtitle: 'Jun 12 – Jun 19',
            leading: Icon(Icons.flight),
            trailing: Icon(Icons.chevron_right),
          ),
        ),
      ),
    );

    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('Jun 12 – Jun 19'), findsOneWidget);
    expect(find.byIcon(Icons.flight), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('omits the subtitle widget when none is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppListRow(title: 'Tokyo')),
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.subtitle, isNull);
  });

  testWidgets('calls onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppListRow(title: 'Rome', onTap: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byType(AppListRow));
    expect(tapped, isTrue);
  });
}
