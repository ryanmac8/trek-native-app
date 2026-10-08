import 'package:flutter/material.dart';

import '../app_spacing.dart';
import '../formats/currency.dart';
import 'date_time_fields.dart';

/// `EUR (€)` — how Trek's web client labels a currency in its pickers; just
/// the code when the currency has no symbol of its own (`CHF`).
String currencyLabel(String code) {
  final upper = code.toUpperCase();
  final symbol = Currency.symbol(upper);
  return symbol == upper ? upper : '$upper ($symbol)';
}

/// A form field showing an ISO 4217 currency (e.g. a trip's `currency`) that
/// opens [showCurrencyPicker] when tapped. Like [DateField], the parent owns
/// [value] and rebuilds with whatever [onChanged] reports.
class CurrencyField extends StatelessWidget {
  const CurrencyField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Currency',
    this.enabled = true,
    this.errorText,
  });

  /// The selected code, or null when nothing is selected.
  final String? value;

  /// Called with the picked code. Not called when the picker is dismissed
  /// without a choice.
  final ValueChanged<String> onChanged;
  final String label;
  final bool enabled;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final picked = await showCurrencyPicker(
      context: context,
      selected: value,
      title: label,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final code = value;
    return PickerField(
      label: label,
      icon: Icons.payments_outlined,
      text: code == null || code.isEmpty ? null : currencyLabel(code),
      onTap: () => _pick(context),
      enabled: enabled,
      errorText: errorText,
    );
  }
}

/// Opens a searchable bottom sheet over Trek's selectable currencies
/// ([Currency.selectableWith] [selected], so a saved code outside the list
/// stays pickable) and returns the chosen code, or null when dismissed.
Future<String?> showCurrencyPicker({
  required BuildContext context,
  String? selected,
  String title = 'Currency',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _CurrencyPickerSheet(selected: selected, title: title),
    ),
  );
}

class _CurrencyPickerSheet extends StatefulWidget {
  const _CurrencyPickerSheet({required this.selected, required this.title});

  final String? selected;
  final String title;

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  String _query = '';

  late final List<String> _codes = Currency.selectableWith(widget.selected);

  /// Codes matching [_query] by code or symbol, with exact code matches
  /// first so typing `usd` puts USD on top. With no query, the current
  /// selection leads the list so it's visible without scrolling.
  List<String> get _matches {
    final query = _query.trim().toUpperCase();
    if (query.isEmpty) {
      final selected = widget.selected?.toUpperCase();
      if (selected == null || !_codes.contains(selected)) return _codes;
      return [selected, ..._codes.where((code) => code != selected)];
    }
    final hits = _codes
        .where(
          (code) =>
              code.contains(query) ||
              Currency.symbol(code).toUpperCase().contains(query),
        )
        .toList();
    hits.sort((a, b) {
      final aExact = a == query ? 0 : 1;
      final bExact = b == query ? 0 : 1;
      return aExact != bExact ? aExact - bExact : a.compareTo(b);
    });
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected?.toUpperCase();
    final matches = _matches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: TextField(
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Search code or symbol',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (text) => setState(() => _query = text),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: matches.isEmpty
              ? const Center(child: Text('No matching currency'))
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final code = matches[index];
                    final isSelected = code == selected;
                    return ListTile(
                      title: Text(code),
                      subtitle: Currency.symbol(code) == code
                          ? null
                          : Text(Currency.symbol(code)),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      selected: isSelected,
                      onTap: () => Navigator.of(context).pop(code),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
