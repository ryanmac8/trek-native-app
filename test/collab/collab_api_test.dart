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
}
