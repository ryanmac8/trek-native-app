import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../formats/currency.dart';

/// A money input for one [currency]: shows the currency's symbol, only
/// accepts digits plus that currency's decimal places, and writes the
/// decimal part with the currency's own separator (`4,90 €`, `$4.90`,
/// `¥500`) whichever of `,`/`.` the keyboard sends.
///
/// Reports amounts as numbers via [onChanged] (null while empty), ready to
/// send as a JSON number such as a budget item's `total_price`. Works inside
/// a [Form]: [required] makes an empty field fail validation.
class CurrencyAmountField extends StatefulWidget {
  const CurrencyAmountField({
    super.key,
    required this.currency,
    required this.onChanged,
    this.initialValue,
    this.label = 'Amount',
    this.required = false,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  /// ISO 4217 code, e.g. a trip's `currency`.
  final String currency;

  /// Seeds the field once, formatted per [Currency.toInputText]. Later
  /// changes to this value don't overwrite what the user has typed.
  final num? initialValue;
  final ValueChanged<double?> onChanged;
  final String label;
  final bool required;
  final bool enabled;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CurrencyAmountField> createState() => _CurrencyAmountFieldState();
}

class _CurrencyAmountFieldState extends State<CurrencyAmountField> {
  late final TextEditingController _controller = TextEditingController(
    text: Currency.toInputText(widget.initialValue, widget.currency),
  );

  @override
  void didUpdateWidget(CurrencyAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currency != widget.currency) {
      // Keep the typed amount, but write it with the new currency's
      // separator. Surplus decimals are left for the validator to flag
      // rather than silently rounding the user's number away. Deferred past
      // this build: editing the controller notifies the enclosing Form.
      final separator = Currency.decimalSeparator(widget.currency);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.text = _controller.text.replaceAll(
          RegExp('[.,]'),
          separator,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? text) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return widget.required ? 'Enter an amount' : null;
    if (Currency.parseInput(value) == null) return 'Enter a valid amount';
    final decimals = Currency.decimals(widget.currency);
    final fraction = value.split(RegExp('[.,]'));
    if (fraction.length > 1 && fraction[1].length > decimals) {
      return decimals == 0
          ? '${widget.currency} amounts have no decimal places'
          : 'Use at most $decimals decimal places';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final decimals = Currency.decimals(widget.currency);
    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
      inputFormatters: [CurrencyAmountInputFormatter(widget.currency)],
      validator: _validate,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: '${Currency.symbol(widget.currency)} ',
        hintText: Currency.toInputText(0, widget.currency),
      ),
      onChanged: (text) => widget.onChanged(Currency.parseInput(text)),
    );
  }
}

/// Restricts input to an amount in [currency]: digits, then at most one
/// decimal separator followed by at most [Currency.decimals] digits. Either
/// `,` or `.` is accepted and rewritten to [Currency.decimalSeparator]; any
/// other edit is rejected (the previous value is kept).
class CurrencyAmountInputFormatter extends TextInputFormatter {
  CurrencyAmountInputFormatter(this.currency);

  final String currency;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final decimals = Currency.decimals(currency);
    final separator = Currency.decimalSeparator(currency);
    // A one-for-one character swap, so the selection stays valid.
    final text = newValue.text.replaceAll(RegExp('[.,]'), separator);
    final pattern = decimals == 0
        ? RegExp(r'^\d*$')
        : RegExp('^\\d*(${RegExp.escape(separator)}\\d{0,$decimals})?\$');
    if (!pattern.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  }
}
