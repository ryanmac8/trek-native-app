import 'package:flutter/material.dart';

/// Trek's default place categories, in seed order — mirrors the
/// `categories` table default rows in Trek's backend
/// (`server/src/db/seeds.ts`). Users can add custom categories on top of
/// these; this list only covers the fixed defaults.
enum PlaceCategory {
  hotel('Hotel', Color(0xFF3B82F6), '🏨'),
  restaurant('Restaurant', Color(0xFFEF4444), '🍽️'),
  attraction('Attraction', Color(0xFF8B5CF6), '🏛️'),
  shopping('Shopping', Color(0xFFF59E0B), '🛍️'),
  transport('Transport', Color(0xFF6B7280), '🚌'),
  activity('Activity', Color(0xFF10B981), '🎯'),
  barCafe('Bar/Cafe', Color(0xFFF97316), '☕'),
  beach('Beach', Color(0xFF06B6D4), '🏖️'),
  nature('Nature', Color(0xFF84CC16), '🌿'),
  other('Other', Color(0xFF6366F1), '📍');

  const PlaceCategory(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final String icon;
}
