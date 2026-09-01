import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/place_category_colors.dart';

void main() {
  group('PlaceCategory', () {
    // Verified against Trek's actual default category seed data
    // (server/src/db/seeds.ts) rather than the (slightly wrong) list in
    // issue #2 — "Cafe" there was a copy-paste error; the real category is
    // "Bar/Cafe" with color #f97316 and icon ☕.
    const expected = {
      PlaceCategory.hotel: (label: 'Hotel', color: 0xFF3B82F6, icon: '🏨'),
      PlaceCategory.restaurant: (
        label: 'Restaurant',
        color: 0xFFEF4444,
        icon: '🍽️',
      ),
      PlaceCategory.attraction: (
        label: 'Attraction',
        color: 0xFF8B5CF6,
        icon: '🏛️',
      ),
      PlaceCategory.shopping: (
        label: 'Shopping',
        color: 0xFFF59E0B,
        icon: '🛍️',
      ),
      PlaceCategory.transport: (
        label: 'Transport',
        color: 0xFF6B7280,
        icon: '🚌',
      ),
      PlaceCategory.activity: (
        label: 'Activity',
        color: 0xFF10B981,
        icon: '🎯',
      ),
      PlaceCategory.barCafe: (label: 'Bar/Cafe', color: 0xFFF97316, icon: '☕'),
      PlaceCategory.beach: (label: 'Beach', color: 0xFF06B6D4, icon: '🏖️'),
      PlaceCategory.nature: (label: 'Nature', color: 0xFF84CC16, icon: '🌿'),
      PlaceCategory.other: (label: 'Other', color: 0xFF6366F1, icon: '📍'),
    };

    for (final entry in expected.entries) {
      test('${entry.key.name} matches the backend seed data', () {
        expect(entry.key.label, entry.value.label);
        expect(entry.key.color, Color(entry.value.color));
        expect(entry.key.icon, entry.value.icon);
      });
    }

    test('covers exactly Trek\'s 10 default categories, no more/fewer', () {
      expect(PlaceCategory.values, hasLength(10));
    });
  });
}
