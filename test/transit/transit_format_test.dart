import 'package:flutter_test/flutter_test.dart';
import 'package:trek/transit/transit_format.dart';
import 'package:trek/transit/transit_models.dart';

void main() {
  group('formatDuration', () {
    test('formats sub-hour, whole-hour and mixed durations', () {
      expect(formatDuration(0), '0m');
      expect(formatDuration(2700), '45m');
      expect(formatDuration(3600), '1h');
      expect(formatDuration(4500), '1h 15m');
    });

    test('rounds to the nearest minute', () {
      expect(formatDuration(89), '1m');
    });
  });

  group('formatClock', () {
    test('renders an ISO timestamp as local HH:mm', () {
      final iso = DateTime(2026, 8, 30, 14, 5).toUtc().toIso8601String();
      expect(formatClock(iso), '14:05');
    });

    test('degrades to --:-- for a missing or unparseable value', () {
      expect(formatClock(null), '--:--');
      expect(formatClock(''), '--:--');
      expect(formatClock('not a date'), '--:--');
    });
  });

  group('formatMode', () {
    test('title-cases a single word and an underscored mode', () {
      expect(formatMode('RAIL'), 'Rail');
      expect(formatMode('AERIAL_LIFT'), 'Aerial lift');
    });
  });

  group('itinerarySummary', () {
    test('joins scheduled legs with their line labels', () {
      const itinerary = TransitItinerary(
        startTime: 'a',
        endTime: 'b',
        legs: [
          TransitLeg(
            mode: 'WALK',
            from: TransitLegStop(name: 'x'),
            to: TransitLegStop(name: 'y'),
          ),
          TransitLeg(
            mode: 'BUS',
            from: TransitLegStop(name: 'y'),
            to: TransitLegStop(name: 'z'),
            line: '5',
          ),
          TransitLeg(
            mode: 'RAIL',
            from: TransitLegStop(name: 'z'),
            to: TransitLegStop(name: 'w'),
            line: 'ICE 72',
          ),
        ],
      );

      expect(itinerarySummary(itinerary), 'Bus 5 → Rail ICE 72');
    });

    test('falls back to Walk for a walk-only journey', () {
      const itinerary = TransitItinerary(
        startTime: 'a',
        endTime: 'b',
        legs: [
          TransitLeg(
            mode: 'WALK',
            from: TransitLegStop(name: 'x'),
            to: TransitLegStop(name: 'y'),
          ),
        ],
      );

      expect(itinerarySummary(itinerary), 'Walk');
    });
  });

  group('transferLabel', () {
    test('handles direct, single and plural', () {
      expect(transferLabel(0), 'Direct');
      expect(transferLabel(1), '1 transfer');
      expect(transferLabel(3), '3 transfers');
    });
  });
}
