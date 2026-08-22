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
        pendingChecked: true,
      );

      final restored = TodoItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, item.id);
      expect(restored.localId, item.localId);
      expect(restored.tripId, item.tripId);
      expect(restored.name, item.name);
      expect(restored.category, item.category);
      expect(restored.checked, item.checked);
      expect(restored.pendingChecked, item.pendingChecked);
    });

    test('a still-pending item round-trips with a null id', () {
      const item = TodoItem(localId: 'local-1', tripId: '20', name: 'Draft');

      final restored = TodoItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.isPending, isTrue);
    });

    test(
      'pendingChecked defaults to false when absent from older cache data',
      () {
        const item = TodoItem(
          id: 5,
          localId: 'server-5',
          tripId: '20',
          name: 'Book campsite',
        );
        final withoutKey = item.toCacheJson()..remove('pending_checked');

        final restored = TodoItem.fromCacheJson(withoutKey);

        expect(restored.pendingChecked, isFalse);
      },
    );

    test(
      'pendingDelete defaults to false when absent from older cache data',
      () {
        const item = TodoItem(
          id: 5,
          localId: 'server-5',
          tripId: '20',
          name: 'Book campsite',
        );
        final withoutKey = item.toCacheJson()..remove('pending_delete');

        final restored = TodoItem.fromCacheJson(withoutKey);

        expect(restored.pendingDelete, isFalse);
      },
    );

    test('a pending-delete item round-trips with the flag set', () {
      const item = TodoItem(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        name: 'Book campsite',
        pendingDelete: true,
      );

      final restored = TodoItem.fromCacheJson(item.toCacheJson());

      expect(restored.pendingDelete, isTrue);
    });
  });

  group('copyWithChecked', () {
    test(
      'replaces checked and pendingChecked, leaving other fields intact',
      () {
        const item = TodoItem(
          id: 5,
          localId: 'server-5',
          tripId: '20',
          name: 'Book campsite',
          category: 'Logistics',
          checked: false,
        );

        final toggled = item.copyWithChecked(true, pendingChecked: true);

        expect(toggled.checked, isTrue);
        expect(toggled.pendingChecked, isTrue);
        expect(toggled.id, item.id);
        expect(toggled.localId, item.localId);
        expect(toggled.name, item.name);
        expect(toggled.category, item.category);
      },
    );

    test('pendingChecked defaults to false', () {
      const item = TodoItem(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        name: 'Book campsite',
        pendingChecked: true,
      );

      final toggled = item.copyWithChecked(false);

      expect(toggled.pendingChecked, isFalse);
    });
  });

  group('copyWithPendingDelete', () {
    test('replaces pendingDelete, leaving other fields intact', () {
      const item = TodoItem(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        name: 'Book campsite',
        category: 'Logistics',
        checked: true,
      );

      final deleted = item.copyWithPendingDelete(true);

      expect(deleted.pendingDelete, isTrue);
      expect(deleted.id, item.id);
      expect(deleted.localId, item.localId);
      expect(deleted.name, item.name);
      expect(deleted.category, item.category);
      expect(deleted.checked, item.checked);
    });
  });
}
