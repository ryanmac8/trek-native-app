import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/collab/collab_api.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

CollabApi _api(http.Client httpClient) {
  return CollabApi(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: httpClient,
    ),
  );
}

void main() {
  group('listNotes', () {
    test(
      'GETs the trip-scoped notes endpoint and parses the wrapped list',
      () async {
        Uri? requestedUri;
        final api = _api(
          MockClient((request) async {
            requestedUri = request.url;
            return _json({
              'notes': [
                {
                  'id': 1,
                  'trip_id': 20,
                  'title': 'Packing reminders',
                  'pinned': 0,
                },
              ],
            });
          }),
        );

        final notes = await api.listNotes('20');

        expect(requestedUri?.path, '/api/trips/20/collab/notes');
        expect(notes.single.title, 'Packing reminders');
        expect(notes.single.tripId, '20');
      },
    );

    test(
      'a trip with no notes yet returns an empty list, not an error',
      () async {
        final api = _api(MockClient((request) async => _json({'notes': []})));

        expect(await api.listNotes('20'), isEmpty);
      },
    );

    test('a 404 (trip not found) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'Trip not found'}, 404)),
      );

      expect(api.listNotes('999'), throwsA(isA<ApiException>()));
    });
  });

  group('createNote', () {
    test(
      'POSTs only the provided fields and parses the created note',
      () async {
        Map<String, dynamic>? sentBody;
        final api = _api(
          MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'note': {
                'id': 7,
                'trip_id': 20,
                'title': 'Packing reminders',
                'content': 'Bring sunscreen',
                'category': 'Logistics',
                'color': '#6366f1',
                'pinned': 0,
              },
            }, 201);
          }),
        );

        final note = await api.createNote(
          '20',
          title: 'Packing reminders',
          content: 'Bring sunscreen',
          category: 'Logistics',
          color: '#6366f1',
        );

        expect(sentBody, {
          'title': 'Packing reminders',
          'content': 'Bring sunscreen',
          'category': 'Logistics',
          'color': '#6366f1',
        });
        expect(note.id, 7);
        expect(note.category, 'Logistics');
      },
    );

    test('omits optional fields entirely when not provided', () async {
      Map<String, dynamic>? sentBody;
      final api = _api(
        MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'note': {'id': 7, 'trip_id': 20, 'title': 'Packing reminders'},
          }, 201);
        }),
      );

      await api.createNote('20', title: 'Packing reminders');

      expect(sentBody, {'title': 'Packing reminders'});
    });

    test('a missing title surfaces the server\'s 400 message', () async {
      final api = _api(
        MockClient(
          (request) async => _json({'error': 'Title is required'}, 400),
        ),
      );

      await expectLater(
        api.createNote('20', title: ''),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Title is required',
          ),
        ),
      );
    });
  });

  group('updateNote', () {
    test('PUTs to the note-scoped endpoint and parses the result', () async {
      Uri? requestedUri;
      String? method;
      Map<String, dynamic>? sentBody;
      final api = _api(
        MockClient((request) async {
          requestedUri = request.url;
          method = request.method;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'note': {
              'id': 7,
              'trip_id': 20,
              'title': 'Packing reminders (updated)',
              'content': 'Bring sunscreen and a hat',
              'category': 'Logistics',
              'pinned': 0,
            },
          });
        }),
      );

      final note = await api.updateNote(
        '20',
        7,
        title: 'Packing reminders (updated)',
        content: 'Bring sunscreen and a hat',
        category: 'Logistics',
      );

      expect(requestedUri?.path, '/api/trips/20/collab/notes/7');
      expect(method, 'PUT');
      expect(sentBody, {
        'title': 'Packing reminders (updated)',
        'content': 'Bring sunscreen and a hat',
        'category': 'Logistics',
      });
      expect(note.title, 'Packing reminders (updated)');
    });

    test('always sends content, even blank, so it can be cleared', () async {
      Map<String, dynamic>? sentBody;
      final api = _api(
        MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'note': {'id': 7, 'trip_id': 20, 'title': 'Packing reminders'},
          });
        }),
      );

      await api.updateNote('20', 7, title: 'Packing reminders');

      expect(sentBody, {'title': 'Packing reminders', 'content': ''});
    });

    test('a 404 (note not found) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'Note not found'}, 404)),
      );

      expect(
        api.updateNote('20', 999, title: 'x'),
        throwsA(isA<ServerException>()),
      );
    });

    test('a 403 (no edit permission) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'No permission'}, 403)),
      );

      expect(
        api.updateNote('20', 7, title: 'x'),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });

  group('deleteNote', () {
    test('DELETEs the note-scoped endpoint', () async {
      Uri? requestedUri;
      String? method;
      final api = _api(
        MockClient((request) async {
          requestedUri = request.url;
          method = request.method;
          return _json({'success': true});
        }),
      );

      await api.deleteNote('20', 7);

      expect(requestedUri?.path, '/api/trips/20/collab/notes/7');
      expect(method, 'DELETE');
    });

    test('a 404 (already deleted) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'Note not found'}, 404)),
      );

      expect(api.deleteNote('20', 999), throwsA(isA<ServerException>()));
    });
  });
}
