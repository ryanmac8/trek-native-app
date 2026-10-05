import 'package:flutter/material.dart';

/// A form field showing a calendar date that opens the platform date picker
/// when tapped. Holds no state of its own: the parent owns [value] and
/// rebuilds with whatever [onChanged] reports, so it composes with any
/// state-management approach. Convert to/from Trek's `YYYY-MM-DD` wire
/// format with `TrekDateTime`.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.initialPickerDate,
    this.clearable = false,
    this.enabled = true,
    this.errorText,
  });

  final String label;

  /// The selected day, or null when nothing is selected. Only the
  /// year/month/day are used.
  final DateTime? value;

  /// Called with the picked day (as local midnight), or null when cleared.
  /// Not called when the picker is dismissed without a choice.
  final ValueChanged<DateTime?> onChanged;

  /// Pickable range. Defaults to ten years either side of today.
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// The day the picker opens on while [value] is null — e.g. a trip's start
  /// date when picking its end date. Defaults to today.
  final DateTime? initialPickerDate;

  /// Shows a clear button while a value is selected.
  final bool clearable;
  final bool enabled;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = DateUtils.dateOnly(firstDate ?? DateTime(now.year - 10));
    final last = DateUtils.dateOnly(
      lastDate ?? DateTime(now.year + 10, 12, 31),
    );
    var initial = DateUtils.dateOnly(value ?? initialPickerDate ?? now);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: label,
    );
    if (picked != null) onChanged(DateUtils.dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final date = value;
    return _PickerField(
      label: label,
      icon: Icons.calendar_today_outlined,
      text: date == null
          ? null
          : '${localizations.formatMediumDate(date)}, '
                '${localizations.formatYear(date)}',
      onTap: () => _pick(context),
      onClear: clearable ? () => onChanged(null) : null,
      enabled: enabled,
      errorText: errorText,
    );
  }
}

/// A form field showing a wall-clock time that opens the platform time
/// picker when tapped. Like [DateField], the parent owns [value]. Displays in
/// the device's 12/24-hour preference; convert to/from Trek's `HH:MM` wire
/// format with `TrekDateTime`.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.initialPickerTime = const TimeOfDay(hour: 9, minute: 0),
    this.clearable = false,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final TimeOfDay? value;

  /// Called with the picked time, or null when cleared. Not called when the
  /// picker is dismissed without a choice.
  final ValueChanged<TimeOfDay?> onChanged;

  /// The time the picker opens on while [value] is null.
  final TimeOfDay initialPickerTime;
  final bool clearable;
  final bool enabled;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: value ?? initialPickerTime,
      helpText: label,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final time = value;
    return _PickerField(
      label: label,
      icon: Icons.schedule_outlined,
      text: time == null
          ? null
          : MaterialLocalizations.of(context).formatTimeOfDay(
              time,
              alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                context,
              ),
            ),
      onTap: () => _pick(context),
      onClear: clearable ? () => onChanged(null) : null,
      enabled: enabled,
      errorText: errorText,
    );
  }
}

/// The shared look of [DateField]/[TimeField]: a read-only input decorated
/// like a text field, so pickers and typed fields line up in one form.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.text,
    required this.onTap,
    required this.onClear,
    required this.enabled,
    required this.errorText,
  });

  final String label;
  final IconData icon;
  final String? text;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final showClear = onClear != null && text != null && enabled;
    return Semantics(
      button: true,
      label: label,
      value: text,
      excludeSemantics: !showClear,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          isEmpty: text == null,
          decoration: InputDecoration(
            labelText: label,
            enabled: enabled,
            errorText: errorText,
            prefixIcon: Icon(icon),
            suffixIcon: showClear
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear $label',
                    onPressed: onClear,
                  )
                : null,
          ),
          child: Text(text ?? ''),
        ),
      ),
    );
  }
}
