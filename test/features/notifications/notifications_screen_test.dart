import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/notifications/notifications_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/notifications/notifications_api.dart';
import 'package:trek/notifications/notifications_repository.dart';
import 'package:trek/notifications/trek_notification.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _row(int id, {bool read = false, String actor = 'Sam'}) =>
    {
      'id': id,
      'type': 'navigate',
      'title_key': 'notif.trip_invite.title',
      'title_params': jsonEncode({'actor': actor, 'trip': 'New Zealand'}),
      'text_key': 'notif.trip_invite.text',
      'text_params': jsonEncode({'actor': actor, 'trip': 'New Zealand'}),
      'is_read': read ? 1 : 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

Future<void> _pump(
  WidgetTester tester, {
  http.Client? httpClient,
  InMemoryNotificationsLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsRepositoryProvider.overrideWithValue(
          NotificationsRepository(
            notificationsApi: NotificationsApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient:
                    httpClient ??
                    MockClient(
                      (_) async => _json({
                        'notifications': [],
                        'total': 0,
                        'unread_count': 0,
                      }),
                    ),
              ),
            ),
            localStore: localStore ?? InMemoryNotificationsLocalStore(),
          ),
        ),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders rendered title + body from the i18n keys', (
    tester,
  ) async {
    await _pump(
      tester,
      httpClient: MockClient(
        (_) async => _json({
          'notifications': [_row(1)],
          'total': 1,
          'unread_count': 1,
        }),
      ),
    );

    expect(find.text('Trip Invitation'), findsOneWidget);
    expect(
      find.textContaining('Sam invited you to New Zealand'),
      findsOneWidget,
    );
  });

  testWidgets('shows the caught-up empty state when there is nothing', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text("You're all caught up."), findsOneWidget);
  });

  testWidgets('shows an explicit offline state with nothing cached', (
    tester,
  ) async {
    await _pump(
      tester,
      httpClient: MockClient((_) async => throw http.ClientException('x')),
    );

    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('paints cached notifications even when the refresh fails', (
    tester,
  ) async {
    await _pump(
      tester,
      httpClient: MockClient((_) async => throw http.ClientException('x')),
      localStore: InMemoryNotificationsLocalStore(
        notifications: [
          TrekNotification(
            id: 1,
            type: 'simple',
            titleKey: 'notif.trip_reminder.title',
            textKey: 'notif.trip_reminder.text',
            textParams: const {'trip': 'Kyoto'},
          ),
        ],
      ),
    );

    expect(find.text('Trip Reminder'), findsOneWidget);
  });

  testWidgets('"Mark all read" marks everything read and hits read-all', (
    tester,
  ) async {
    var readAllCalls = 0;
    await _pump(
      tester,
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          readAllCalls++;
          expect(request.url.path, '/api/notifications/in-app/read-all');
          return _json({'success': true, 'count': 2});
        }
        return _json({
          'notifications': [_row(1), _row(2)],
          'total': 2,
          'unread_count': 2,
        });
      }),
    );

    expect(find.text('Mark all read'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(readAllCalls, 1);
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('tapping an unread notification marks just that one read', (
    tester,
  ) async {
    final marked = <String>[];
    await _pump(
      tester,
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          marked.add(request.url.path);
          return _json({'success': true});
        }
        return _json({
          'notifications': [_row(1)],
          'total': 1,
          'unread_count': 1,
        });
      }),
    );

    await tester.tap(find.text('Trip Invitation'));
    await tester.pumpAndSettle();

    expect(marked, ['/api/notifications/in-app/1/read']);
  });
}
