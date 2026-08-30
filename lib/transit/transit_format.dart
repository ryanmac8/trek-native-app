import 'transit_models.dart';

/// Presentation helpers for transit results — kept separate from the widget
/// so they're unit-testable without a widget tree.

/// `4500` → `"1h 15m"`, `2700` → `"45m"`, `0` → `"0m"`. Rounds to the
/// nearest minute.
String formatDuration(int seconds) {
  final totalMinutes = (seconds / 60).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// An ISO-8601 timestamp → local `"HH:mm"`. Returns `"--:--"` when the
/// value is missing or unparseable, so a flaky provider timestamp never
/// blanks the row.
String formatClock(String? isoTimestamp) {
  if (isoTimestamp == null || isoTimestamp.isEmpty) return '--:--';
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return '--:--';
  final local = parsed.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// `"RAIL"` → `"Rail"`, `"AERIAL_LIFT"` → `"Aerial lift"`. A best-effort
/// label for a MOTIS mode string.
String formatMode(String mode) {
  final words = mode
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .join(' ');
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}

/// The compact "Bus 5 → Rail ICE 72" style summary of an itinerary's
/// scheduled legs. Falls back to "Walk" for a walk-only journey.
String itinerarySummary(TransitItinerary itinerary) {
  final legs = itinerary.transitLegs;
  if (legs.isEmpty) return 'Walk';
  return legs
      .map((leg) {
        final label = formatMode(leg.mode);
        return leg.line == null ? label : '$label ${leg.line}';
      })
      .join(' → ');
}

/// `"2 transfers"`, `"1 transfer"`, `"Direct"`.
String transferLabel(int transfers) {
  if (transfers <= 0) return 'Direct';
  return transfers == 1 ? '1 transfer' : '$transfers transfers';
}
