import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/budget/budget_api.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

BudgetApi _api(http.Client httpClient) {
  return BudgetApi(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: httpClient,
    ),
  );
}

void main() {
  group('listItems', () {
    test('GETs the trip-scoped endpoint and parses the wrapped list', () async {
      Uri? requestedUri;
      final api = _api(
        MockClient((request) async {
          requestedUri = request.url;
          return _json({
            'items': [
              {
                'id': 1,
                'trip_id': 20,
                'name': 'Rental car',
                'total_price': 300,
              },
            ],
          });
        }),
      );

      final items = await api.listItems('20');

      expect(requestedUri?.path, '/api/trips/20/budget');
      expect(items.single.name, 'Rental car');
      expect(items.single.tripId, '20');
    });

    test('an empty trip budget returns an empty list, not an error', () async {
      final api = _api(MockClient((request) async => _json({'items': []})));

      expect(await api.listItems('20'), isEmpty);
    });

    test('a 404 (trip not found) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'Trip not found'}, 404)),
      );

      expect(api.listItems('999'), throwsA(isA<ApiException>()));
    });
  });

  group('createItem', () {
    test(
      'POSTs only the provided fields and parses the created item',
      () async {
        Map<String, dynamic>? sentBody;
        final api = _api(
          MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'item': {
                'id': 7,
                'trip_id': 20,
                'name': 'Dinner',
                'category': 'food',
                'total_price': 42.5,
              },
            }, 201);
          }),
        );

        final item = await api.createItem(
          '20',
          name: 'Dinner',
          category: 'food',
          totalPrice: 42.5,
        );

        expect(sentBody, {
          'name': 'Dinner',
          'category': 'food',
          'total_price': 42.5,
        });
        expect(item.id, 7);
        expect(item.category, 'food');
      },
    );

    test('omits optional fields entirely when not provided', () async {
      Map<String, dynamic>? sentBody;
      final api = _api(
        MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'item': {'id': 7, 'trip_id': 20, 'name': 'Dinner'},
          }, 201);
        }),
      );

      await api.createItem('20', name: 'Dinner');

      expect(sentBody, {'name': 'Dinner'});
    });

    test('a missing name surfaces the server\'s 400 message', () async {
      final api = _api(
        MockClient(
          (request) async => _json({'error': 'Name is required'}, 400),
        ),
      );

      await expectLater(
        api.createItem('20', name: ''),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Name is required',
          ),
        ),
      );
    });
  });
}
