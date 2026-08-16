import 'package:flutter_test/flutter_test.dart';
import 'package:trek/packing/packing_item.dart';

void main() {
  group('PackingItem.fromJson', () {
    test('parses the real API shape', () {
      final item = PackingItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Hiking boots',
        'category': 'Footwear',
        'checked': 1,
        'sort_order': 0,
        'quantity': 1,
        'is_private': 0,
      }, tripId: '20');

      expect(item.id, 5);
      expect(item.localId, 'server-5');
      expect(item.tripId, '20');
      expect(item.name, 'Hiking boots');
      expect(item.category, 'Footwear');
      expect(item.checked, isTrue);
      expect(item.isPending, isFalse);
    });

    test('checked defaults to false when absent or 0', () {
      final unchecked = PackingItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Passport',
        'checked': 0,
      }, tripId: '20');
      final absent = PackingItem.fromJson({
        'id': 6,
        'trip_id': 20,
        'name': 'Passport',
      }, tripId: '20');

      expect(unchecked.checked, isFalse);
      expect(absent.checked, isFalse);
    });

    test('category is null when absent', () {
      final item = PackingItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Passport',
      }, tripId: '20');

      expect(item.category, isNull);
    });
  });

  group('isPending', () {
    test('is true for a locally-created item with no server id yet', () {
      const item = PackingItem(localId: 'local-1', tripId: '20', name: 'Draft');

      expect(item.isPending, isTrue);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every field', () {
      const item = PackingItem(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        name: 'Hiking boots',
        category: 'Footwear',
        checked: true,
      );

      final restored = PackingItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, item.id);
      expect(restored.localId, item.localId);
      expect(restored.tripId, item.tripId);
      expect(restored.name, item.name);
      expect(restored.category, item.category);
      expect(restored.checked, item.checked);
    });

    test('a still-pending item round-trips with a null id', () {
      const item = PackingItem(localId: 'local-1', tripId: '20', name: 'Draft');

      final restored = PackingItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.isPending, isTrue);
    });
  });
}
