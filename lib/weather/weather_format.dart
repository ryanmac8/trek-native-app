import 'package:flutter/material.dart';

import 'weather_models.dart';

/// Presentation helpers for weather — icon mapping, temperature and date
/// formatting. Kept out of the widgets so they can be unit-tested without a
/// widget tree. The app has no locale system yet, so everything here is
/// English and metric (matching the `lang=en` the API layer sends).

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A Material icon for a condition bucket. Mirrors the web client's
/// `WEATHER_ICON_MAP` (`client/src/components/Weather/WeatherWidget.tsx`).
IconData weatherIcon(WeatherCondition condition) {
  switch (condition) {
    case WeatherCondition.clear:
      return Icons.wb_sunny_outlined;
    case WeatherCondition.clouds:
      return Icons.cloud_outlined;
    case WeatherCondition.rain:
      return Icons.umbrella_outlined;
    case WeatherCondition.drizzle:
      return Icons.grain_outlined;
    case WeatherCondition.snow:
      return Icons.ac_unit_outlined;
    case WeatherCondition.fog:
      return Icons.foggy;
    case WeatherCondition.thunderstorm:
      return Icons.thunderstorm_outlined;
    case WeatherCondition.unknown:
      return Icons.help_outline;
  }
}

/// Whole degrees with a degree sign, e.g. `18°C`. The server has already
/// rounded; this just formats.
String formatTemp(int celsius) => '$celsius°C';

/// A high/low pair, e.g. `21° / 12°`. Falls back to the single [temp] when the
/// report carries no range (current conditions).
String formatRange(WeatherReport report) {
  final max = report.tempMax;
  final min = report.tempMin;
  if (max == null || min == null) return formatTemp(report.temp);
  return '$max° / $min°';
}

/// `Mon 3 Jun`, or `Today` / `Tomorrow` relative to [reference] (defaults to
/// `DateTime.now()`). [date] and [reference] are compared by calendar day.
String formatForecastDay(DateTime date, {DateTime? reference}) {
  final now = reference ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  final weekday = _weekdays[target.weekday - 1];
  final month = _months[target.month - 1];
  return '$weekday ${target.day} $month';
}

/// A short human label for what kind of answer this is, or null for a plain
/// forecast that needs no qualifier.
String? weatherQualifier(WeatherReport report) {
  if (report.isMissing) return 'No forecast available';
  if (report.isEstimate) return 'Seasonal average';
  return null;
}
