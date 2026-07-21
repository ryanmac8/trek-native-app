import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/app_colors.dart';
import 'package:trek/design/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses light brightness derived from the seed color', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
    });

    test('dark theme uses dark brightness derived from the seed color', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('both themes derive their scheme from the same seed color', () {
      expect(
        ColorScheme.fromSeed(
          seedColor: AppColors.seed,
          brightness: Brightness.light,
        ).primary,
        AppTheme.light.colorScheme.primary,
      );
      expect(
        ColorScheme.fromSeed(
          seedColor: AppColors.seed,
          brightness: Brightness.dark,
        ).primary,
        AppTheme.dark.colorScheme.primary,
      );
    });

    test('uses Material 3', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });
  });
}
