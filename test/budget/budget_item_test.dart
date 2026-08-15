import 'package:flutter_test/flutter_test.dart';
import 'package:trek/budget/budget_item.dart';

void main() {
  group('BudgetItem.fromJson', () {
    test('parses the real API shape', () {
      final item = BudgetItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'category': 'food',
        'name': 'Dinner',
        'total_price': 42.5,
        'currency': 'EUR',
        'persons': 2,
        'days': null,
        'note': 'Group dinner',
        'sort_order': 0,
        'expense_date': '2026-08-20',
      }, tripId: '20');

      expect(item.id, 5);
      expect(item.localId, 'server-5');
      expect(item.tripId, '20');
      expect(item.category, 'food');
      expect(item.name, 'Dinner');
      expect(item.totalPrice, 42.5);
      expect(item.currency, 'EUR');
      expect(item.persons, 2);
      expect(item.note, 'Group dinner');
      expect(item.expenseDate, '2026-08-20');
      expect(item.isPending, isFalse);
    });

    test('optional fields are null when absent', () {
      final item = BudgetItem.fromJson({
        'id': 5,
        'trip_id': 20,
        'name': 'Dinner',
      }, tripId: '20');

      expect(item.category, isNull);
      expect(item.totalPrice, isNull);
      expect(item.currency, isNull);
      expect(item.persons, isNull);
      expect(item.days, isNull);
      expect(item.note, isNull);
      expect(item.expenseDate, isNull);
    });
  });

  group('isPending', () {
    test('is true for a locally-created item with no server id yet', () {
      const item = BudgetItem(localId: 'local-1', tripId: '20', name: 'Draft');

      expect(item.isPending, isTrue);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every field', () {
      const item = BudgetItem(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        name: 'Dinner',
        category: 'food',
        totalPrice: 42.5,
        currency: 'EUR',
        persons: 2,
        days: 1,
        note: 'Group dinner',
        expenseDate: '2026-08-20',
      );

      final restored = BudgetItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, item.id);
      expect(restored.localId, item.localId);
      expect(restored.tripId, item.tripId);
      expect(restored.name, item.name);
      expect(restored.category, item.category);
      expect(restored.totalPrice, item.totalPrice);
      expect(restored.currency, item.currency);
      expect(restored.persons, item.persons);
      expect(restored.days, item.days);
      expect(restored.note, item.note);
      expect(restored.expenseDate, item.expenseDate);
    });

    test('a still-pending item round-trips with a null id', () {
      const item = BudgetItem(localId: 'local-1', tripId: '20', name: 'Draft');

      final restored = BudgetItem.fromCacheJson(item.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.isPending, isTrue);
    });
  });
}
