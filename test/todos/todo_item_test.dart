import 'package:flutter_test/flutter_test.dart';
import 'package:trek/todos/todo_item.dart';

void main() {
  group('TodoItem.fromJson', () {
    test('parses the real API shape', () {
      final item = TodoItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Book campsite',
        'category': 'Logistics',
        'checked': 1,
        'sort_order': 0,
        'priority': 0,
      }, tripId: '20');

      expect(item.id, 5);
      expect(item.localId, 'server-5');
      expect(item.tripId, '20');
      expect(item.name, 'Book campsite');
      expect(item.category, 'Logistics');
      expect(item.checked, isTrue);
      expect(item.isPending, isFalse);
    });

    test('checked defaults to false when absent or 0', () {
      final unchecked = TodoItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Buy tickets',
        'checked': 0,
      }, tripId: '20');
      final absent = TodoItem.fromJson({
        'id': 6,
        'trip_id': 20,
        'name': 'Buy tickets',
      }, tripId: '20');

      expect(unchecked.checked, isFalse);
      expect(absent.checked, isFalse);
    });

    test('category is null when absent', () {
      final item = TodoItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Buy tickets',
      }, tripId: '20');

      expect(item.category, isNull);
    });
  });

  group('isPending', () {
    test('is true for a locally-created item with no server id yet', () {
      const item = TodoItem(localId: 'local-1', tripId: '20', name: 'Draft');

      expect(item.isPending, isTrue);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every field', () {
      const item = TodoItem(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        name: 'Book campsite',
        category: 'Logistics',
        checked: true,
      );

      final restored = TodoItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, item.id);
      expect(restored.localId, item.localId);
      expect(restored.tripId, item.tripId);
      expect(restored.name, item.name);
      expect(restored.category, item.category);
      expect(restored.checked, item.checked);
    });

    test('a still-pending item round-trips with a null id', () {
      const item = TodoItem(localId: 'local-1', tripId: '20', name: 'Draft');

      final restored = TodoItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.isPending, isTrue);
    });
  });
}
