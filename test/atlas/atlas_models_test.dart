import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trek/atlas/atlas_models.dart';

import 'atlas_fixtures.dart';

void main() {
  group('AtlasStats.fromJson', () {
    test('parses the full stats response', () {
      final stats = AtlasStats.fromJson(fullStatsJson());

      expect(stats.totalTrips, 5);
      expect(stats.totalPlaces, 17);
      expect(stats.totalCountries, 1);
      expect(stats.totalCountriesPlanned, 1);
      expect(stats.totalCountriesIdea, 1);
      expect(stats.totalDays, 23);
      expect(stats.totalCities, 6);
      expect(stats.countries.map((c) => c.status), [
        VisitStatus.visited,
        VisitStatus.planned,
        VisitStatus.idea,
      ]);
      expect(stats.mostVisited!.code, 'NZ');
      expect(stats.mostVisited!.placeCount, 12);
      expect(stats.continents, {'Oceania': 1});
      expect(stats.continentsPlanned, {'Asia': 1});
      expect(stats.lastTrip!.title, 'New Zealand');
      expect(stats.lastTrip!.countryCode, 'NZ');
      expect(stats.nextTrip!.title, 'Japan');
      expect(stats.nextTrip!.startDate, '2026-10-04');
      expect(stats.streak, 3);
      expect(stats.firstYear, 2024);
      expect(stats.tripsThisYear, 2);
      expect(stats.isEmpty, isFalse);
    });

    test('tolerates the reduced zero-trip response', () {
      final stats = AtlasStats.fromJson(zeroTripStatsJson());

      expect(stats.totalTrips, 0);
      expect(stats.totalCountries, 1);
      expect(stats.totalCities, 0);
      expect(stats.countries.single.code, 'FR');
      // Only manually marked countries appear here, which Trek treats as
      // visited.
      expect(stats.countries.single.status, VisitStatus.visited);
      expect(stats.mostVisited, isNull);
      expect(stats.lastTrip, isNull);
      expect(stats.nextTrip, isNull);
      expect(stats.continents, isEmpty);
      expect(stats.firstYear, isNull);
      expect(stats.isEmpty, isFalse);
    });

    test('isEmpty with no trips and no countries', () {
      final stats = AtlasStats.fromJson({
        'countries': <dynamic>[],
        'stats': {'totalTrips': 0},
      });
      expect(stats.isEmpty, isTrue);
    });
  });

  test('CachedAtlasStats survives a JSON round-trip', () {
    final original = CachedAtlasStats(
      stats: AtlasStats.fromJson(fullStatsJson()),
      fetchedAt: DateTime.utc(2026, 9, 24, 8, 30),
    );

    final restored = CachedAtlasStats.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored.fetchedAt, DateTime.utc(2026, 9, 24, 8, 30));
    expect(restored.stats.toJson(), original.stats.toJson());
  });

  group('trip countdowns', () {
    const next = AtlasNextTrip(id: 1, title: 'Japan', startDate: '2026-10-04');
    const last = AtlasLastTrip(id: 2, title: 'NZ', endDate: '2026-09-20');

    test('daysUntil counts calendar days regardless of time of day', () {
      expect(next.daysUntil(DateTime(2026, 9, 24, 23, 59)), 10);
      expect(next.daysUntil(DateTime(2026, 10, 4, 0, 1)), 0);
      expect(next.daysUntil(DateTime(2026, 10, 6)), -2);
    });

    test('daysSinceEnd counts calendar days since the end date', () {
      expect(last.daysSinceEnd(DateTime(2026, 9, 24, 7)), 4);
    });

    test('are null without dates', () {
      expect(
        const AtlasNextTrip(id: 1, title: 'x').daysUntil(DateTime(2026)),
        isNull,
      );
      expect(
        const AtlasLastTrip(id: 1, title: 'x').daysSinceEnd(DateTime(2026)),
        isNull,
      );
    });
  });

  test('countryFlag builds regional-indicator emoji', () {
    expect(countryFlag('nz'), '🇳🇿');
    expect(countryFlag('XK1'), 'XK1');
  });
}
