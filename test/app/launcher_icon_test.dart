import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _res = 'android/app/src/main/res';

/// Android density buckets → the adaptive layer size (108dp) in pixels.
const _layerSizes = {
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};

img.Image _decode(String path) => img.decodePng(File(path).readAsBytesSync())!;

void main() {
  group('Android adaptive launcher icon', () {
    test('mipmap-anydpi-v26 declares background, foreground and monochrome '
        'layers with no extra inset', () {
      final xml = File(
        '$_res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();

      expect(xml, contains('<adaptive-icon'));
      expect(
        xml,
        contains(
          '<background android:drawable="@drawable/ic_launcher_background"/>',
        ),
      );
      expect(xml, contains('@drawable/ic_launcher_foreground'));
      expect(xml, contains('@drawable/ic_launcher_monochrome'));
      expect(
        RegExp(r'android:inset="(\d+)%"').allMatches(xml).map((m) => m[1]),
        everyElement('0'),
      );
    });

    for (final entry in _layerSizes.entries) {
      test('${entry.key} has every layer at ${entry.value}px plus the legacy '
          'icon', () {
        for (final layer in ['background', 'foreground', 'monochrome']) {
          final png = _decode(
            '$_res/drawable-${entry.key}/ic_launcher_$layer.png',
          );
          expect(png.width, entry.value, reason: layer);
          expect(png.height, entry.value, reason: layer);
        }
        // Pre-Android 8 launchers still use the full-bleed legacy icon.
        expect(
          File('$_res/mipmap-${entry.key}/ic_launcher.png').existsSync(),
          isTrue,
        );
      });
    }

    test('foreground mark stays inside the 66dp safe zone', () {
      final fg = _decode('assets/icon/adaptive_foreground.png');
      final center = fg.width / 2;
      final safeRadius = fg.width * 33 / 108;

      var maxRadius = 0.0;
      for (final p in fg) {
        if (p.a == 0) continue;
        final r = math.sqrt(
          math.pow(p.x + 0.5 - center, 2) + math.pow(p.y + 0.5 - center, 2),
        );
        maxRadius = math.max(maxRadius, r);
      }

      expect(maxRadius, greaterThan(0), reason: 'foreground is empty');
      expect(maxRadius, lessThanOrEqualTo(safeRadius));
    });

    test('foreground is a white mark on transparent, usable as the '
        'monochrome layer', () {
      final fg = _decode('assets/icon/adaptive_foreground.png');

      expect(fg.getPixel(0, 0).a, 0);
      for (final p in fg) {
        if (p.a == 255) {
          expect([p.r, p.g, p.b], [255, 255, 255]);
        }
      }
    });

    test('background is the opaque splash gradient, #1E293B → #0F172A', () {
      final bg = _decode('assets/icon/adaptive_background.png');
      final topLeft = bg.getPixel(0, 0);
      final bottomRight = bg.getPixel(bg.width - 1, bg.height - 1);

      expect([topLeft.r, topLeft.g, topLeft.b], [0x1E, 0x29, 0x3B]);
      expect([bottomRight.r, bottomRight.g, bottomRight.b], [0x0F, 0x17, 0x2A]);
      for (final p in bg) {
        expect(p.a, 255);
      }
    });
  });
}
