import 'package:flutter/material.dart';

import '../app_spacing.dart';
import '../formats/trek_date_range.dart';
import 'date_time_fields.dart';

/// A start/end date pair — e.g. a trip's dates — as two [DateField]s that
/// keep the range consistent the way Trek's web trip form does (see
/// [TrekDateRange.withStart]): picking a start drags the end along, and the
/// end picker can't go before the start (or past [maxDays]).
///
/// Stateless like [DateField]: the parent owns [value] and rebuilds with
/// whatever [onChanged] reports. A range that is invalid anyway (e.g. one
/// loaded from elsewhere with its end before its start) shows
/// [TrekDateRange.validate]'s message under the end field, unless
/// [errorText] overrides it.
class DateRangeField extends StatelessWidget {
  const DateRangeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.startLabel = 'Start date',
    this.endLabel = 'End date',
    this.maxDays = TrekDateRange.maxTripDays,
    this.clearable = true,
    this.enabled = true,
    this.errorText,
  });

  final TrekDateRange value;
  final ValueChanged<TrekDateRange> onChanged;
  final String startLabel;
  final String endLabel;

  /// Longest allowed span in days, both ends included; null for no limit.
  final int? maxDays;

  /// Shows a clear button on each field while it has a value. Trek trips
  /// may be undated, so this defaults to true.
  final bool clearable;
  final bool enabled;

  /// Shown under the end field in place of the range's own validation.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final start = value.start;
    final limit = maxDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateField(
          label: startLabel,
          value: start,
          initialPickerDate: value.end,
          clearable: clearable,
          enabled: enabled,
          onChanged: (day) => onChanged(value.withStart(day)),
        ),
        const SizedBox(height: AppSpacing.md),
        DateField(
          label: endLabel,
          value: value.end,
          firstDate: start,
          lastDate: start != null && limit != null
              ? DateTime(start.year, start.month, start.day + limit - 1)
              : null,
          initialPickerDate: start,
          clearable: clearable,
          enabled: enabled,
          errorText: errorText ?? value.validate(maxDays: maxDays),
          onChanged: (day) => onChanged(value.withEnd(day)),
        ),
      ],
    );
  }
}
