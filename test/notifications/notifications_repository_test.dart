import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/notifications/notifications_api.dart';
import 'package:trek/notifications/notifications_repository.dart';
import 'package:trek/notifications/trek_notification.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _row(int id, {bool read = false}) => {
  'id': id,
  'type': 'simple',
  'title_key': 'notif.generic.title',
  'title_params': '{}',
  'text_key': 'notif.generic.text',
  'text_params': '{}',
  'is_read': read ? 1 : 0,
  'created_at': '2026-08-29T10:00:00.000Z',
};

TrekNotification _cached(int id, {bool isRead = false}) => TrekNotification(
  id: id,
  type: 'simple',
  titleKey: 'notif.generic.title',
  textKey: 'notif.generic.text',
  isRead: isRead,
);

NotificationsRepository _repository({
  required http.Client httpClient,
  InMemoryNotificationsLocalStore? localStore,
}) {
  return NotificationsRepository(
    notificationsApi: NotificationsApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryNotificationsLocalStore(),
  );
}

http.Client _offline() =>
    MockClient((_) async => throw http.ClientException('offline'));

void main() {
  group('cachedNotifications', () {
    test('reads the local store without touching the network', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('should not hit the network')),
        localStore: InMemoryNotificationsLocalStore(
          notifications: [_cached(1)],
        ),
      );

      expect((await repository.cachedNotifications()).single.id, 1);
    });

    test('layers queued pending reads on top of the cached list', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('no network')),
        localStore: InMemoryNotificationsLocalStore(
          notifications: [_cached(1), _cached(2)],
          pendingReads: {2},
        ),
      );

      final cached = await repository.cachedNotifications();

      expect(cached.firstWhere((n) => n.id == 2).isRead, isTrue);
      expect(cached.firstWhere((n) => n.id == 1).isRead, isFalse);
      expect(await repository.cachedUnreadCount(), 1);
    });
  });

  group('refreshNotifications', () {
    test('fetches the first page and writes it to the cache', () async {
      final localStore = InMemoryNotificationsLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/notifications/in-app');
          return _json({
            'notifications': [_row(1), _row(2, read: true)],
            'total': 2,
            'unread_count': 1,
          });
        }),
        localStore: localStore,
      );

      final result = await repository.refreshNotifications();

      expect(result.map((n) => n.id), [1, 2]);
      expect((await localStore.readNotifications()).map((n) => n.id), [1, 2]);
    });

    test(
      'falls back to the cache on NetworkException when non-empty',
      () async {
        final repository = _repository(
          httpClient: _offline(),
          localStore: InMemoryNotificationsLocalStore(
            notifications: [_cached(5)],
          ),
        );

        expect((await repository.refreshNotifications()).single.id, 5);
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(httpClient: _offline());

      expect(
        repository.refreshNotifications(),
        throwsA(isA<NetworkException>()),
      );
    });

    test('flushes queued reads to the server before fetching', () async {
      final marked = <int>[];
      final localStore = InMemoryNotificationsLocalStore(
        notifications: [_cached(1, isRead: true)],
        pendingReads: {1},
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            marked.add(int.parse(request.url.pathSegments[3]));
            return _json({'success': true});
          }
          return _json({
            'notifications': [_row(1, read: true)],
            'total': 1,
            'unread_count': 0,
          });
        }),
        localStore: localStore,
      );

      await repository.refreshNotifications();

      expect(marked, [1]);
      expect(await localStore.readPendingReads(), isEmpty);
    });
  });

  group('markRead (offline-first write)', () {
    test(
      'applies locally and clears the queue when the server accepts',
      () async {
        final localStore = InMemoryNotificationsLocalStore(
          notifications: [_cached(1), _cached(2)],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            expect(request.method, 'PUT');
            expect(request.url.path, '/api/notifications/in-app/1/read');
            return _json({'success': true});
          }),
          localStore: localStore,
        );

        await repository.markRead(1);

        expect(
          (await localStore.readNotifications())
              .firstWhere((n) => n.id == 1)
              .isRead,
          isTrue,
        );
        expect(await localStore.readPendingReads(), isEmpty);
      },
    );

    test('still applies locally and stays queued when offline', () async {
      final localStore = InMemoryNotificationsLocalStore(
        notifications: [_cached(1)],
      );
      final repository = _repository(
        httpClient: _offline(),
        localStore: localStore,
      );

      await repository.markRead(1);

      expect((await localStore.readNotifications()).single.isRead, isTrue);
      expect(await localStore.readPendingReads(), {1});
      // The optimistic read is still visible after a "restart".
      expect(await repository.cachedUnreadCount(), 0);
    });

    test('drops the id from the queue on a non-network API error', () async {
      final localStore = InMemoryNotificationsLocalStore(
        notifications: [_cached(1)],
      );
      final repository = _repository(
        httpClient: MockClient((_) async => _json({'error': 'Not found'}, 404)),
        localStore: localStore,
      );

      await repository.markRead(1);

      expect(await localStore.readPendingReads(), isEmpty);
    });
  });

  group('markAllRead', () {
    test('marks every cached notification read and syncs once', () async {
      var calls = 0;
      final localStore = InMemoryNotificationsLocalStore(
        notifications: [_cached(1), _cached(2), _cached(3, isRead: true)],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/notifications/in-app/read-all');
          return _json({'success': true, 'count': 2});
        }),
        localStore: localStore,
      );

      await repository.markAllRead();

      expect(
        (await localStore.readNotifications()).every((n) => n.isRead),
        isTrue,
      );
      expect(await localStore.readPendingReads(), isEmpty);
      expect(calls, 1);
    });

    test('keeps the unread ids queued when offline', () async {
      final localStore = InMemoryNotificationsLocalStore(
        notifications: [_cached(1), _cached(2)],
      );
      final repository = _repository(
        httpClient: _offline(),
        localStore: localStore,
      );

      await repository.markAllRead();

      expect(
        (await localStore.readNotifications()).every((n) => n.isRead),
        isTrue,
      );
      expect(await localStore.readPendingReads(), {1, 2});
    });

    test('is a no-op when nothing is unread', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('nothing to sync')),
        localStore: InMemoryNotificationsLocalStore(
          notifications: [_cached(1, isRead: true)],
        ),
      );

      await repository.markAllRead();
    });
  });
}
