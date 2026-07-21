import 'package:flutter/material.dart';

/// Brand and semantic color tokens, independent of [PlaceCategory] colors
/// (which come from Trek's backend category data, not this palette).
abstract final class AppColors {
  /// Seed color for [ColorScheme.fromSeed] — drives both light and dark
  /// Material 3 schemes in [AppTheme].
  static const seed = Color(0xFF0D9488);

  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
}
