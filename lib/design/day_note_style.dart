import 'package:flutter/material.dart';

/// Trek's day-note icon set and color palette, as offered by the web
/// client's note dialog (`NOTE_ICONS` in
/// `client/src/components/Planner/DayPlanSidebar.constants.ts`, and
/// `NOTE_COLORS` in `shared/src/day/note-colors.ts`), mapped to Material
/// equivalents. Notes store the lucide icon name, so these keys must match
/// the web client's exactly for a note to look the same on both.
abstract final class DayNoteStyle {
  static const Map<String, IconData> icons = {
    'FileText': Icons.description_outlined,
    'Info': Icons.info_outline,
    'Clock': Icons.schedule,
    'MapPin': Icons.place_outlined,
    'Navigation': Icons.navigation_outlined,
    'Train': Icons.train_outlined,
    'Plane': Icons.flight,
    'Bus': Icons.directions_bus_outlined,
    'Car': Icons.directions_car_outlined,
    'Ship': Icons.directions_boat_outlined,
    'Coffee': Icons.local_cafe_outlined,
    'Ticket': Icons.confirmation_number_outlined,
    'Star': Icons.star_outline,
    'Heart': Icons.favorite_outline,
    'Camera': Icons.photo_camera_outlined,
    'Flag': Icons.flag_outlined,
    'Lightbulb': Icons.lightbulb_outline,
    'AlertTriangle': Icons.warning_amber,
    'ShoppingBag': Icons.shopping_bag_outlined,
    'Bookmark': Icons.bookmark_outline,
    'Utensils': Icons.restaurant,
    'Wine': Icons.wine_bar_outlined,
    'ParkingSquare': Icons.local_parking,
    'Fuel': Icons.local_gas_station_outlined,
    'Footprints': Icons.directions_walk,
    'Mountain': Icons.terrain_outlined,
    'Waves': Icons.waves,
    'Sun': Icons.wb_sunny_outlined,
    'Umbrella': Icons.beach_access_outlined,
    'Music': Icons.music_note_outlined,
    'Landmark': Icons.account_balance_outlined,
    'Gift': Icons.card_giftcard,
  };

  /// The server keeps a note's color only if it's one of these.
  static const List<Color> colors = [
    Color(0xFFDC2626),
    Color(0xFFEA580C),
    Color(0xFFD97706),
    Color(0xFF16A34A),
    Color(0xFF0891B2),
    Color(0xFF2563EB),
    Color(0xFF9333EA),
  ];

  /// The `#rrggbb` form the API stores.
  static String hex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// Parses an API color; `null` for no color or anything unparseable.
  static Color? parse(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return null;
    }
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  /// The note's icon: its lucide name mapped to Material, a stored emoji
  /// shown as text, or the web client's `FileText` fallback.
  static Widget iconFor(String? icon, {Color? color, double size = 20}) {
    final mapped = icon == null ? null : icons[icon];
    if (mapped != null) return Icon(mapped, color: color, size: size);
    if (icon != null &&
        icon.isNotEmpty &&
        !RegExp(r'^[A-Za-z]').hasMatch(icon)) {
      return Text(icon, style: TextStyle(fontSize: size * 0.9));
    }
    return Icon(icons['FileText'], color: color, size: size);
  }
}
