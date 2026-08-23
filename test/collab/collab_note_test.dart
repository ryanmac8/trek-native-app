import 'package:flutter_test/flutter_test.dart';
import 'package:trek/collab/collab_note.dart';

void main() {
  group('CollabNote.fromJson', () {
    test('parses the real API shape', () {
      final note = CollabNote.fromJson({
        'id': 5,
        'trip_id': 20,
        'title': 'Packing reminders',
        'content': "Don't forget sunscreen",
        'category': 'Logistics',
        'color': '#6366f1',
        'pinned': 1,
        'username': 'alex',
      }, tripId: '20');

      expect(note.id, 5);
      expect(note.localId, 'server-5');
      expect(note.tripId, '20');
      expect(note.title, 'Packing reminders');
      expect(note.content, "Don't forget sunscreen");
      expect(note.category, 'Logistics');
      expect(note.color, '#6366f1');
      expect(note.pinned, isTrue);
      expect(note.authorUsername, 'alex');
      expect(note.isPending, isFalse);
    });

    test('pinned defaults to false when absent or 0', () {
      final unpinned = CollabNote.fromJson({
        'id': 5,
        'trip_id': 20,
        'title': 'Note',
        'pinned': 0,
      }, tripId: '20');
      final absent = CollabNote.fromJson({
        'id': 6,
        'trip_id': 20,
        'title': 'Note',
      }, tripId: '20');

      expect(unpinned.pinned, isFalse);
      expect(absent.pinned, isFalse);
    });

    test('content, category, color, and author are null when absent', () {
      final note = CollabNote.fromJson({
        'id': 5,
        'trip_id': 20,
        'title': 'Note',
      }, tripId: '20');

      expect(note.content, isNull);
      expect(note.category, isNull);
      expect(note.color, isNull);
      expect(note.authorUsername, isNull);
    });
  });

  group('isPending', () {
    test('is true for a locally-created note with no server id yet', () {
      const note = CollabNote(localId: 'local-1', tripId: '20', title: 'Draft');

      expect(note.isPending, isTrue);
    });

    test('is false once a server id is assigned', () {
      const note = CollabNote(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        title: 'Synced',
      );

      expect(note.isPending, isFalse);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every field', () {
      const note = CollabNote(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        title: 'Packing reminders',
        content: "Don't forget sunscreen",
        category: 'Logistics',
        color: '#6366f1',
        pinned: true,
        authorUsername: 'alex',
      );

      final restored = CollabNote.fromCacheJson(note.toCacheJson());

      expect(restored.id, note.id);
      expect(restored.localId, note.localId);
      expect(restored.tripId, note.tripId);
      expect(restored.title, note.title);
      expect(restored.content, note.content);
      expect(restored.category, note.category);
      expect(restored.color, note.color);
      expect(restored.pinned, note.pinned);
      expect(restored.authorUsername, note.authorUsername);
    });

    test('a still-pending note round-trips with a null id', () {
      const note = CollabNote(localId: 'local-1', tripId: '20', title: 'Draft');

      final restored = CollabNote.fromCacheJson(note.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.isPending, isTrue);
    });

    test('pinned defaults to false when absent from older cache data', () {
      const note = CollabNote(
        id: 5,
        localId: 'server-5',
        tripId: '20',
        title: 'Packing reminders',
      );
      final withoutKey = note.toCacheJson()..remove('pinned');

      final restored = CollabNote.fromCacheJson(withoutKey);

      expect(restored.pinned, isFalse);
    });
  });
}
