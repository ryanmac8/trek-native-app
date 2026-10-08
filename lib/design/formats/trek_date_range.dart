import 'package:flutter/foundation.dart';

/// A start/end pair of calendar days, either of which may be unset — the
/// shape of a trip's `start_date`/`end_date` (both `YYYY-MM-DD` or null; see
/// `TrekDateTime`). Holds the date-range rules Trek's web trip form and
/// server apply, so a native form edits a range the same way.
@immutable
class TrekDateRange {
  const TrekDateRange({this.start, this.end});

  static const empty = TrekDateRange();

  /// The longest range a trip may span, inclusive of both ends
  /// (`MAX_TRIP_DAYS` in Trek's `shared/src/trip/trip.schema.ts`).
  static const maxTripDays = 999;

  /// Local midnight on each day; only the year/month/day parts are used.
  final DateTime? start;
  final DateTime? end;

  /// The number of calendar days from [start] to [end], counting both — 1
  /// for a same-day range, 0 or less when [end] is before [start]. Null
  /// unless both are set. Counted on the calendar, so a DST change inside
  /// the range doesn't shift it.
  int? get spanDays {
    final s = start;
    final e = end;
    if (s == null || e == null) return null;
    return spanBetween(s, e);
  }

  /// [spanDays] for an arbitrary pair of days.
  static int spanBetween(DateTime start, DateTime end) =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;

  /// The range after the user picks [newStart], following Trek's web trip
  /// form: when [end] is unset or would fall before [newStart], it moves to
  /// [newStart]; when both days were already set, [end] moves with the start
  /// so the trip keeps its length; otherwise [end] stays put. Clearing the
  /// start (`null`) leaves [end] alone.
  TrekDateRange withStart(DateTime? newStart) {
    if (newStart == null) return TrekDateRange(end: end);
    final s = _day(newStart);
    final oldStart = start;
    final oldEnd = end;
    if (oldEnd == null || _day(oldEnd).isBefore(s)) {
      return TrekDateRange(start: s, end: s);
    }
    if (oldStart != null) {
      final length = spanBetween(oldStart, oldEnd) - 1;
      return TrekDateRange(
        start: s,
        end: DateTime(s.year, s.month, s.day + length),
      );
    }
    return TrekDateRange(start: s, end: _day(oldEnd));
  }

  /// The range after the user picks (or clears) [newEnd]; [start] is kept.
  TrekDateRange withEnd(DateTime? newEnd) =>
      TrekDateRange(start: start, end: newEnd == null ? null : _day(newEnd));

  /// Why the range can't be saved, or null when it can. Mirrors the
  /// server's trip-range check (`End date must be after start date` /
  /// `A trip can span at most 999 days`); [maxDays] is null for ranges with
  /// no length limit. A range with either day unset isn't checked: on trip
  /// create the server derives the missing day as a 7-day range.
  String? validate({int? maxDays = maxTripDays}) {
    final span = spanDays;
    if (span == null) return null;
    if (span < 1) return 'End date must be after start date';
    if (maxDays != null && span > maxDays) {
      return 'A trip can span at most $maxDays days';
    }
    return null;
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  bool operator ==(Object other) =>
      other is TrekDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TrekDateRange($start, $end)';
}
