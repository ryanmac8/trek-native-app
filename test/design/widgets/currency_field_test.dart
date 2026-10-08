import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/formats/currency.dart';
import 'package:trek/design/widgets/currency_field.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  test('currencyLabel matches the web client picker labels', () {
    expect(currencyLabel('EUR'), 'EUR (€)');
    expect(currencyLabel('usd'), r'USD ($)');
    expect(currencyLabel('CHF'), 'CHF');
    expect(currencyLabel('XYZ'), 'XYZ');
  });

  testWidgets('shows the label and selected currency', (tester) async {
    await tester.pumpWidget(
      _host(CurrencyField(value: 'EUR', onChanged: (_) {})),
    );
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('EUR (€)'), findsOneWidget);
  });

  testWidgets('picks a currency from the sheet via search', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _host(CurrencyField(value: 'EUR', onChanged: (code) => picked = code)),
    );

    await tester.tap(find.byType(CurrencyField));
    await tester.pumpAndSettle();
    // The current selection is marked.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'EUR'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'jp');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'JPY'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'EUR'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'JPY'));
    await tester.pumpAndSettle();
    expect(picked, 'JPY');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('dismissing the sheet reports nothing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(CurrencyField(value: 'EUR', onChanged: (_) => calls++)),
    );
    await tester.tap(find.byType(CurrencyField));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('search matches symbols and puts an exact code first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(CurrencyField(value: null, onChanged: (_) {})),
    );
    await tester.tap(find.byType(CurrencyField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '€');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'EUR'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'usd');
    await tester.pumpAndSettle();
    final first = tester.widget<ListTile>(find.byType(ListTile).first);
    expect((first.title! as Text).data, 'USD');

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching currency'), findsOneWidget);
  });

  testWidgets('a saved code outside the list stays pickable', (tester) async {
    expect(Currency.codes, isNot(contains('HRK')));
    await tester.pumpWidget(
      _host(CurrencyField(value: 'HRK', onChanged: (_) {})),
    );
    await tester.tap(find.byType(CurrencyField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hrk');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'HRK'), findsOneWidget);
  });

  testWidgets('does not open when disabled', (tester) async {
    await tester.pumpWidget(
      _host(CurrencyField(value: 'EUR', enabled: false, onChanged: (_) {})),
    );
    await tester.tap(find.byType(CurrencyField));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
}
