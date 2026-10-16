import 'package:flutter/material.dart';

import '../../places/place.dart';

/// A small circle in a category's color, with its emoji icon when it has
/// one — shared by the place list's category badge and the place form's
/// category picker.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category});

  final PlaceCategoryRef category;

  @override
  Widget build(BuildContext context) {
    final color =
        parseCategoryColor(category.color) ??
        Theme.of(context).colorScheme.primary;
    final emoji = category.emoji;
    return emoji != null
        ? CircleAvatar(
            radius: 12,
            backgroundColor: color,
            child: Text(emoji, style: const TextStyle(fontSize: 12)),
          )
        : CircleAvatar(radius: 6, backgroundColor: color);
  }
}

/// Parses a `#rrggbb` hex string (Trek's category color format — see
/// `server/src/db/seeds.ts`) into a [Color]; `null` if it doesn't match.
Color? parseCategoryColor(String? hex) {
  if (hex == null) return null;
  final normalized = hex.replaceFirst('#', '');
  if (normalized.length != 6) return null;
  final value = int.tryParse(normalized, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
