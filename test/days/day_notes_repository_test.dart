import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/days/day.dart';
import 'package:trek/days/day_note.dart';
import 'package:trek/days/day_note_outbox.dart';
import 'package:trek/days/days_api.dart';
import 'package:trek/days/days_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _noteJson(
  int id, {
  int dayId = 1,
  String text = 'Note',
  String? time,
  String? icon = 'FileText',
  String? color,
  num sortOrder = 9999,
  String createdAt = '2026-10-15 10:00:00',
}) => {
  'id': id,
  'day_id': dayId,
  'trip_id': 20,
  'text': text,
  'time': time,
  'icon': icon,
  'color': color,
  'sort_order': sortOrder,
  'created_at': createdAt,
};

Map<String, dynamic> _dayJson(
  int id, {
  List<Map<String, dynamic>> notes = const [],
}) => {
  'id': id,
  'trip_id': 20,
  'day_number': id,
  'date': null,
  'assignments': const [],
  'notes_items': notes,
};

Day _day(int id, {List<DayNote> notes = const []}) =>
    Day(id: id, tripId: 20, dayNumber: id).withNoteItems(notes);

/// A fake Trek server for one trip's days and notes, mutated by the requests
/// it receives. Set [offline] to make every request fail as unreachable.
class _FakeServer {
  _FakeServer({Map<int, List<Map<String, dynamic>>>? notesByDay})
    : notesByDay = notesByDay ?? {1: [], 2: []};

  final Map<int, List<Map<String, dynamic>>> notesByDay;
  final requests = <http.Request>[];
  bool offline = false;
  int nextId = 100;

  /// Returns a canned response for the next request instead of handling it.
  http.Response? Function(http.Request request)? intercept;

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    requests.add(request);
    final canned = intercept?.call(request);
    if (canned != null) return canned;

    final segments = request.url.pathSegments;
    // api trips 20 days [dayId notes [noteId]]
    if (segments.length == 4 && request.method == 'GET') {
      return _json({
        'days': [
          for (final entry in notesByDay.entries)
            _dayJson(entry.key, notes: entry.value),
        ],
      });
    }
    final dayId = int.parse(segments[4]);
    final notes = notesByDay[dayId];
    if (notes == null) return _json({'error': 'Day not found'}, 404);
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    if (request.method == 'POST') {
      final note = _noteJson(
        nextId++,
        dayId: dayId,
        text: body['text'] as String,
        time: body['time'] as String?,
        icon: body['icon'] as String?,
        color: body['color'] as String?,
      );
      notes.add(note);
      return _json({'note': note}, 201);
    }

    final noteId = int.parse(segments[6]);
    final index = notes.indexWhere((note) => note['id'] == noteId);
    if (index == -1) return _json({'error': 'Note not found'}, 404);
    if (request.method == 'PUT') {
      notes[index] = {...notes[index], ...body};
      return _json({'note': notes[index]});
    }
    notes.removeAt(index);
    return _json({'success': true});
  });
}

void main() {
  late _FakeServer server;
  late InMemoryDaysLocalStore localStore;
  late InMemoryDayNoteOutbox outbox;
  late DaysRepository repository;

  DaysRepository build() => DaysRepository(
    daysApi: DaysApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: server.client,
      ),
    ),
    localStore: localStore,
    noteOutbox: outbox,
    now: () => DateTime.utc(2026, 10, 15, 12),
  );

  setUp(() {
    server = _FakeServer();
    localStore = InMemoryDaysLocalStore(
      initial: {
        '20': [_day(1), _day(2)],
      },
    );
    outbox = InMemoryDayNoteOutbox();
    repository = build();
  });

  Future<List<DayNote>> cachedNotes(int dayId) async {
    final days = await localStore.read('20');
    return days.firstWhere((day) => day.id == dayId).noteItems;
  }

  test('parses notes_items from the days list, in server order', () async {
    server.notesByDay[1] = [
      _noteJson(2, text: 'Second', sortOrder: 2),
      _noteJson(1, text: 'First', sortOrder: 1, color: '#2563eb'),
    ];

    final days = await repository.refreshDays('20');

    final notes = days.first.noteItems;
    expect(notes.map((n) => n.text), ['First', 'Second']);
    expect(notes.first.color, '#2563eb');
    expect(notes.first.isPending, isFalse);
  });

  group('online', () {
    test('create sends the wire body and caches the server copy', () async {
      final note = await repository.createDayNote(
        '20',
        dayId: 1,
        text: '  Lunch  ',
        time: 'Book ahead',
        color: '#16a34a',
      );

      expect(note.id, 100);
      expect(note.isPending, isFalse);
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/trips/20/days/1/notes');
      expect(jsonDecode(request.body), {
        'text': 'Lunch',
        'time': 'Book ahead',
        'icon': 'FileText',
        'color': '#16a34a',
      });
      final cached = await cachedNotes(1);
      expect(cached.single.id, 100);
      expect(cached.single.isPending, isFalse);
      expect(await outbox.read('20'), isEmpty);
    });

    test('update sends only the given fields; null clears', () async {
      server.notesByDay[1] = [_noteJson(7, text: 'Old', time: 'details')];
      await repository.refreshDays('20');
      final note = (await cachedNotes(1)).single;

      final updated = await repository.updateDayNote('20', note, {
        'text': 'New',
        'time': null,
      });

      final request = server.requests.last;
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/trips/20/days/1/notes/7');
      expect(jsonDecode(request.body), {'text': 'New', 'time': null});
      expect(updated.text, 'New');
      expect(updated.time, isNull);
      expect(updated.isPending, isFalse);
    });

    test('delete removes the note locally and on the server', () async {
      server.notesByDay[1] = [_noteJson(7)];
      await repository.refreshDays('20');
      final note = (await cachedNotes(1)).single;

      await repository.deleteDayNote('20', note);

      expect(server.requests.last.method, 'DELETE');
      expect(server.notesByDay[1], isEmpty);
      expect(await cachedNotes(1), isEmpty);
    });

    test('delete of a note already gone server-side still succeeds', () async {
      await localStore.write('20', [
        _day(1, notes: [DayNote.fromJson(_noteJson(7))]),
      ]);

      await repository.deleteDayNote('20', DayNote.fromJson(_noteJson(7)));

      expect(await cachedNotes(1), isEmpty);
      expect(await outbox.read('20'), isEmpty);
    });
  });

  group('offline', () {
    setUp(() => server.offline = true);

    test(
      'create applies locally, stays queued, and is marked pending',
      () async {
        final note = await repository.createDayNote(
          '20',
          dayId: 1,
          text: 'Passport',
        );

        expect(note.id, isNull);
        expect(note.localId, isNotNull);
        expect(note.isPending, isTrue);
        expect((await cachedNotes(1)).single.text, 'Passport');
        expect(await repository.pendingNoteWriteCount('20'), 1);
      },
    );

    test(
      'edits and deletes of an unsynced note fold into its create',
      () async {
        final created = await repository.createDayNote(
          '20',
          dayId: 1,
          text: 'Draft',
        );
        await repository.updateDayNote('20', created, {'text': 'Final'});

        var queued = await outbox.read('20');
        expect(queued.single.kind, DayNoteOpKind.create);
        expect(queued.single.fields['text'], 'Final');
        expect((await cachedNotes(1)).single.text, 'Final');

        await repository.deleteDayNote('20', created);
        queued = await outbox.read('20');
        expect(queued, isEmpty);
        expect(await cachedNotes(1), isEmpty);
      },
    );

    test('refresh keeps the cache and the queue when unreachable', () async {
      await repository.createDayNote('20', dayId: 1, text: 'Passport');

      final days = await repository.refreshDays('20');

      expect(days.first.noteItems.single.text, 'Passport');
      expect(await repository.pendingNoteWriteCount('20'), 1);
    });

    test('refresh with an empty cache and no network rethrows', () async {
      localStore = InMemoryDaysLocalStore();
      repository = build();

      expect(
        () => repository.refreshDays('20'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('queued writes replay in order once back online', () async {
      server.notesByDay[1] = [_noteJson(7, text: 'Existing')];
      await localStore.write('20', [
        _day(1, notes: [DayNote.fromJson(_noteJson(7, text: 'Existing'))]),
        _day(2),
      ]);
      final existing = (await cachedNotes(1)).single;

      await repository.updateDayNote('20', existing, {'color': '#dc2626'});
      await repository.createDayNote('20', dayId: 2, text: 'Ferry');
      expect(await repository.pendingNoteWriteCount('20'), 2);

      server.offline = false;
      final days = await repository.refreshDays('20');

      expect(server.requests.map((r) => r.method), ['PUT', 'POST', 'GET']);
      expect(await repository.pendingNoteWriteCount('20'), 0);
      expect(days[0].noteItems.single.color, '#dc2626');
      expect(days[0].noteItems.single.isPending, isFalse);
      expect(days[1].noteItems.single.id, 100);
      expect(days[1].noteItems.single.isPending, isFalse);
    });

    test('a refresh that fails mid-sync re-applies the rest of the queue '
        'on top of the server read', () async {
      await repository.createDayNote('20', dayId: 1, text: 'One');
      await repository.createDayNote('20', dayId: 1, text: 'Two');

      server.offline = false;
      var posts = 0;
      server.intercept = (request) {
        if (request.method == 'POST' && ++posts == 2) {
          return _json({'error': 'down'}, 503);
        }
        return null;
      };
      final days = await repository.refreshDays('20');

      final notes = days.first.noteItems;
      expect(notes.map((n) => n.text), ['One', 'Two']);
      expect(notes[0].isPending, isFalse);
      expect(notes[1].isPending, isTrue);
      expect(await repository.pendingNoteWriteCount('20'), 1);
    });

    test('an expired session keeps the write queued', () async {
      server.offline = false;
      server.intercept = (request) =>
          _json({'error': 'Invalid or expired token'}, 401);

      final note = await repository.createDayNote(
        '20',
        dayId: 1,
        text: 'Keep me',
      );

      expect(note.isPending, isTrue);
      expect(await repository.pendingNoteWriteCount('20'), 1);
    });

    test('an edit made against a stale pre-sync copy targets the synced '
        'note', () async {
      final stale = await repository.createDayNote(
        '20',
        dayId: 1,
        text: 'Draft',
      );
      server.offline = false;
      await repository.refreshDays('20');
      // The refresh replaced the cache with the server read, but the
      // screen may still hold `stale` (local id only) — re-seed the cache
      // with the synced note carrying that local id, as a flush leaves it.
      await localStore.write('20', [
        _day(
          1,
          notes: [
            DayNote.fromJson(
              _noteJson(100, text: 'Draft'),
            ).withLocalId(stale.localId),
          ],
        ),
        _day(2),
      ]);

      await repository.updateDayNote('20', stale, {'text': 'Final'});

      expect(server.requests.last.method, 'PUT');
      expect(server.requests.last.url.path, endsWith('/notes/100'));
    });
  });

  group('rejections', () {
    test('a rejected create is rolled back and rethrown', () async {
      server.intercept = (request) => request.method == 'POST'
          ? _json({'error': 'Text required'}, 400)
          : null;

      await expectLater(
        repository.createDayNote('20', dayId: 1, text: 'x'),
        throwsA(isA<ValidationException>()),
      );
      expect(await cachedNotes(1), isEmpty);
      expect(await outbox.read('20'), isEmpty);
    });

    test('a create on a day deleted server-side is dropped', () async {
      server.notesByDay.remove(2);

      await expectLater(
        repository.createDayNote('20', dayId: 2, text: 'x'),
        throwsA(isA<ServerException>()),
      );
      expect(await outbox.read('20'), isEmpty);
      final days = await localStore.read('20');
      expect(days.map((d) => d.id), [1]);
    });

    test('a forbidden update is reverted to the server copy', () async {
      server.notesByDay[1] = [_noteJson(7, text: 'Theirs')];
      await repository.refreshDays('20');
      final note = (await cachedNotes(1)).single;
      server.intercept = (request) => request.method == 'PUT'
          ? _json({'error': 'No permission'}, 403)
          : null;

      await expectLater(
        repository.updateDayNote('20', note, {'text': 'Mine'}),
        throwsA(isA<ForbiddenException>()),
      );
      expect((await cachedNotes(1)).single.text, 'Theirs');
    });
  });

  group('DayNoteOutbox.enqueue', () {
    const update7 = DayNoteOp(
      kind: DayNoteOpKind.update,
      dayId: 1,
      noteId: 7,
      fields: {'text': 'A'},
    );

    test('merges successive updates to the same note', () {
      final ops = DayNoteOutbox.enqueue(
        [update7],
        const DayNoteOp(
          kind: DayNoteOpKind.update,
          dayId: 1,
          noteId: 7,
          fields: {'color': null},
        ),
      );
      expect(ops.single.fields, {'text': 'A', 'color': null});
    });

    test('a delete replaces a queued update', () {
      final ops = DayNoteOutbox.enqueue([
        update7,
      ], const DayNoteOp(kind: DayNoteOpKind.delete, dayId: 1, noteId: 7));
      expect(ops.single.kind, DayNoteOpKind.delete);
    });

    test('drops a local-id update with no queued create to fold into', () {
      final ops = DayNoteOutbox.enqueue(
        const [],
        const DayNoteOp(
          kind: DayNoteOpKind.update,
          dayId: 1,
          localId: 'local-1',
          fields: {'text': 'A'},
        ),
      );
      expect(ops, isEmpty);
    });

    test('ops round-trip through JSON', () {
      const op = DayNoteOp(
        kind: DayNoteOpKind.create,
        dayId: 3,
        localId: 'local-1',
        createdAt: '2026-10-15 12:00:00',
        fields: {'text': 'A', 'time': null},
      );
      final restored = DayNoteOp.fromJson(
        jsonDecode(jsonEncode(op.toJson())) as Map<String, dynamic>,
      );
      expect(restored.kind, op.kind);
      expect(restored.localId, op.localId);
      expect(restored.createdAt, op.createdAt);
      expect(restored.fields, op.fields);
    });
  });

  test('cached days keep notes and their pending state', () {
    final day = _day(
      1,
      notes: [
        const DayNote(localId: 'local-1', dayId: 1, text: 'A', isPending: true),
      ],
    );
    final restored = Day.fromCacheJson(
      jsonDecode(jsonEncode(day.toCacheJson())) as Map<String, dynamic>,
    );
    expect(restored.noteItems.single.localId, 'local-1');
    expect(restored.noteItems.single.isPending, isTrue);
  });
}
