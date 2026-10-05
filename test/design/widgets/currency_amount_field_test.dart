import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/widgets/currency_amount_field.dart';

Widget _host(Widget child, {GlobalKey<FormState>? formKey}) => MaterialApp(
  home: Scaffold(
    body: Form(key: formKey, child: child),
  ),
);

String _text(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

void main() {
  testWidgets('seeds from initialValue in the currency’s format', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CurrencyAmountField(
          currency: 'EUR',
          initialValue: 4.9,
          onChanged: (_) {},
        ),
      ),
    );

    expect(_text(tester), '4,90');
    expect(find.text('€ '), findsOneWidget);
  });

  testWidgets('rewrites either separator to the currency’s and reports the '
      'number', (tester) async {
    double? reported;
    await tester.pumpWidget(
      _host(
        CurrencyAmountField(
          currency: 'EUR',
          onChanged: (value) => reported = value,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '12.5');
    expect(_text(tester), '12,5');
    expect(reported, 12.5);
  });

  testWidgets('rejects letters, a second separator, and surplus decimals', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(CurrencyAmountField(currency: 'USD', onChanged: (_) {})),
    );
    final field = find.byType(TextFormField);

    await tester.enterText(field, '3.25');
    await tester.enterText(field, '3.255');
    expect(_text(tester), '3.25');
    await tester.enterText(field, '3.2.5');
    expect(_text(tester), '3.25');
    await tester.enterText(field, '3a');
    expect(_text(tester), '3.25');
  });

  testWidgets('zero-decimal currencies take whole numbers only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(CurrencyAmountField(currency: 'JPY', onChanged: (_) {})),
    );
    final field = find.byType(TextFormField);

    await tester.enterText(field, '500');
    await tester.enterText(field, '500.5');
    expect(_text(tester), '500');
  });

  testWidgets('reports null once cleared', (tester) async {
    double? reported = 1;
    await tester.pumpWidget(
      _host(
        CurrencyAmountField(
          currency: 'USD',
          initialValue: 10,
          onChanged: (value) => reported = value,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '');
    expect(reported, isNull);
  });

  testWidgets('required fails validation while empty', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      _host(
        CurrencyAmountField(currency: 'USD', required: true, onChanged: (_) {}),
        formKey: formKey,
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter an amount'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '7');
    expect(formKey.currentState!.validate(), isTrue);
  });

  testWidgets('an optional empty field is valid', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      _host(
        CurrencyAmountField(currency: 'USD', onChanged: (_) {}),
        formKey: formKey,
      ),
    );

    expect(formKey.currentState!.validate(), isTrue);
  });

  testWidgets('switching currency keeps the amount, swaps the separator, and '
      'flags decimals the new currency lacks', (tester) async {
    final formKey = GlobalKey<FormState>();
    Widget field(String currency) => _host(
      CurrencyAmountField(
        currency: currency,
        initialValue: 4.5,
        onChanged: (_) {},
      ),
      formKey: formKey,
    );

    await tester.pumpWidget(field('USD'));
    expect(_text(tester), '4.50');

    await tester.pumpWidget(field('EUR'));
    expect(_text(tester), '4,50');
    expect(formKey.currentState!.validate(), isTrue);

    await tester.pumpWidget(field('JPY'));
    expect(_text(tester), '4.50');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('JPY amounts have no decimal places'), findsOneWidget);
  });
}
