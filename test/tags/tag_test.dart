import 'package:flutter_test/flutter_test.dart';
import 'package:trek/tags/tag.dart';

void main() {
  group('Tag.fromJson', () {
    test('parses the real API shape', () {
      final tag = Tag.fromJson({
        'id': 5,
        'user_id': 1,
        'name': 'Foodie',
        'color': '#ef4444',
      });

      expect(tag.id, 5);
      expect(tag.localId, 'server-5');
      expect(tag.name, 'Foodie');
      expect(tag.color, '#ef4444');
      expect(tag.isPending, isFalse);
    });

    test('color is null when absent', () {
      final tag = Tag.fromJson({'id': 5, 'user_id': 1, 'name': 'Foodie'});

      expect(tag.color, isNull);
    });
  });

  group('isPending', () {
    test('is true for a locally-created tag with no server id yet', () {
      const tag = Tag(localId: 'local-1', name: 'Draft');

      expect(tag.isPending, isTrue);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every field', () {
      const tag = Tag(
        id: 5,
        localId: 'server-5',
        name: 'Foodie',
        color: '#ef4444',
      );

      final restored = Tag.fromCacheJson(tag.toCacheJson());

      expect(restored.id, tag.id);
      expect(restored.localId, tag.localId);
      expect(restored.name, tag.name);
      expect(restored.color, tag.color);
    });

    test('a still-pending tag round-trips with a null id', () {
      const tag = Tag(localId: 'local-1', name: 'Draft');

      final restored = Tag.fromCacheJson(tag.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.isPending, isTrue);
    });
  });
}
