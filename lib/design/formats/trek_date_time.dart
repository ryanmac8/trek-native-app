import 'package:flutter/material.dart';

/// Conversions between Flutter's date/time types and the string shapes
/// Trek's backend stores: calendar dates as `YYYY-MM-DD` (day dates, trip
/// start/end, vacay entries, expense dates) and wall-clock times as `HH:MM`
/// (assignment start/end times, day-note time labels).
///
/// Dates are calendar days, not instants — they carry no time zone, so they
/// are built and read as local midnight and only the year/month/day parts
/// are ever used.
abstract final class TrekDateTime {
  static final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _time = RegExp(r'^(\d{2}):(\d{2})');
  static final _isoTime = RegExp(r'^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2})');

  /// `2026-03-07` for 7 March 2026.
  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${_two(date.month)}-${_two(date.day)}';

  /// Parses a `YYYY-MM-DD` string to local midnight on that day. Returns
  /// null for null, empty, malformed, or impossible dates (`2026-02-30`).
  static DateTime? parseDate(String? value) {
    final match = _date.firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// `09:05` for 9:05 AM — always 24-hour, zero-padded.
  static String formatTime(TimeOfDay time) =>
      '${_two(time.hour)}:${_two(time.minute)}';

  /// Parses a bare `HH:MM` (seconds, if present, are ignored) or the time
  /// part of a local ISO datetime (`YYYY-MM-DDTHH:MM`), the two shapes Trek
  /// time columns hold. Returns null for anything else or out-of-range
  /// values.
  static TimeOfDay? parseTime(String? value) {
    final text = value?.trim() ?? '';
    final match = _isoTime.firstMatch(text) ?? _time.firstMatch(text);
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
