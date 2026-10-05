import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/formats/currency.dart';

void main() {
  test('decimal places follow Trek’s currency exceptions', () {
    expect(Currency.decimals('EUR'), 2);
    expect(Currency.decimals('usd'), 2);
    expect(Currency.decimals('JPY'), 0);
    expect(Currency.decimals('HUF'), 0);
    expect(Currency.decimals('KWD'), 3);
  });

  test('decimal separator follows the currency, not the device locale', () {
    expect(Currency.decimalSeparator('EUR'), ',');
    expect(Currency.decimalSeparator('BRL'), ',');
    expect(Currency.decimalSeparator('USD'), '.');
    expect(Currency.decimalSeparator('CHF'), '.');
    expect(Currency.decimalSeparator('XYZ'), '.');
  });

  test('symbol falls back to the code', () {
    expect(Currency.symbol('EUR'), '€');
    expect(Currency.symbol('usd'), r'$');
    expect(Currency.symbol('XYZ'), 'XYZ');
  });

  test('every selectable currency has a symbol', () {
    for (final code in Currency.codes) {
      expect(Currency.symbol(code), isNot(isEmpty), reason: code);
    }
  });

  test('selectableWith keeps an unsupported saved currency', () {
    expect(Currency.selectableWith('EUR'), same(Currency.codes));
    expect(Currency.selectableWith(null), same(Currency.codes));
    expect(Currency.selectableWith('hrk').last, 'HRK');
  });

  test('cleanAmount drops float noise from uneven splits', () {
    expect(Currency.cleanAmount(81.61 + 81.60), 163.21);
  });

  group('toInputText', () {
    test('pads to the currency’s decimals with its separator', () {
      expect(Currency.toInputText(4.9, 'EUR'), '4,90');
      expect(Currency.toInputText(5, 'USD'), '5.00');
      expect(Currency.toInputText(500, 'JPY'), '500');
      expect(Currency.toInputText(1.5, 'KWD'), '1.500');
    });

    test('is empty for null and non-finite values', () {
      expect(Currency.toInputText(null, 'EUR'), '');
      expect(Currency.toInputText(double.nan, 'EUR'), '');
      expect(Currency.toInputText(double.infinity, 'EUR'), '');
    });
  });

  group('parseInput', () {
    test('accepts either separator', () {
      expect(Currency.parseInput('4,90'), 4.9);
      expect(Currency.parseInput('4.90'), 4.9);
      expect(Currency.parseInput(' 12 '), 12);
      expect(Currency.parseInput(',5'), 0.5);
    });

    test('reads a trailing separator as the whole number', () {
      expect(Currency.parseInput('12,'), 12);
    });

    test('rejects empty, grouped, signed, and non-numeric text', () {
      for (final text in ['', '1.234,56', '-5', 'abc', '1e3', '.']) {
        expect(Currency.parseInput(text), isNull, reason: text);
      }
    });

    test('round-trips with toInputText', () {
      for (final currency in ['EUR', 'USD', 'JPY', 'KWD']) {
        final text = Currency.toInputText(1234.5, currency);
        expect(
          Currency.toInputText(Currency.parseInput(text), currency),
          text,
          reason: currency,
        );
      }
    });
  });
}
