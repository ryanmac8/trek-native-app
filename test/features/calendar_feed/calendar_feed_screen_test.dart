import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_messenger.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/calendar_feed/calendar_feed.dart';
import 'package:trek/calendar_feed/calendar_feed_api.dart';
import 'package:trek/calendar_feed/calendar_feed_repository.dart';
import 'package:trek/calendar_feed/calendar_subscriber.dart';
import 'package:trek/features/calendar_feed/calendar_feed_screen.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

const _account = 'https://trek.example.com#7';
const _url = 'https://trek.example.com/api/feed/user/tok-1.ics';

class _FakeSubscriber implements CalendarSubscriber {
  _FakeSubscriber({this.result = true});

  final bool result;
  final List<String> urls = [];

  @override
  Future<bool> subscribe(String feedUrl) async {
    urls.add(feedUrl);
    return result;
  }
}

void main() {
  late InMemoryCalendarFeedStore store;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  late _FakeSubscriber subscriber;
  String? clipboard;

  http.Response feed(String? url) =>
      http.Response(jsonEncode({'feed_url': url}), 200);

  setUp(() {
    store = InMemoryCalendarFeedStore();
    requests = [];
    handler = (_) async => feed(null);
    subscriber = _FakeSubscriber();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    CalendarFeedScope scope = const AllTripsFeedScope(),
  }) async {
    final repository = CalendarFeedRepository(
      api: CalendarFeedApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) {
            requests.add(request);
            return handler(request);
          }),
        ),
      ),
      store: store,
      account: () async => _account,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarFeedRepositoryProvider.overrideWithValue(repository),
          calendarSubscriberProvider.overrideWithValue(subscriber),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: CalendarFeedScreen(scope: scope),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String stateLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('calendar-feed-state'))).data!;

  testWidgets('shows an enabled feed and subscribes the calendar', (
    tester,
  ) async {
    handler = (_) async => feed(_url);
    await pumpScreen(tester);

    expect(stateLabel(tester), 'On');
    expect(find.text(_url), findsOneWidget);

    await tester.tap(find.text('Add to calendar'));
    await tester.pumpAndSettle();
    expect(subscriber.urls, [_url]);
  });

  testWidgets('copies the link when no calendar app accepts it', (
    tester,
  ) async {
    handler = (_) async => feed(_url);
    subscriber = _FakeSubscriber(result: false);
    await pumpScreen(tester);

    await tester.tap(find.text('Add to calendar'));
    await tester.pumpAndSettle();

    expect(clipboard, _url);
    expect(find.textContaining('it was copied'), findsOneWidget);
  });

  testWidgets('turning the feed on POSTs and shows the new link', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(stateLabel(tester), 'Off');

    handler = (_) async => feed(_url);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(requests.last.method, 'POST');
    expect(stateLabel(tester), 'On');
    expect(find.text(_url), findsOneWidget);
  });

  testWidgets('turning off asks for confirmation, then DELETEs', (
    tester,
  ) async {
    handler = (_) async => feed(_url);
    await pumpScreen(tester);

    handler = (_) async => feed(null);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Turn off calendar feed?'), findsOneWidget);

    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();

    expect(requests.last.method, 'DELETE');
    expect(stateLabel(tester), 'Off');
    expect(find.text(_url), findsNothing);
  });

  testWidgets('shows the cached link while offline', (tester) async {
    await store.write(
      _account,
      const AllTripsFeedScope(),
      const CalendarFeedSnapshot(feedUrl: _url),
    );
    handler = (_) => throw const SocketException('offline');
    await pumpScreen(tester);

    expect(
      find.text('Offline — showing the last saved state.'),
      findsOneWidget,
    );
    expect(find.text(_url), findsOneWidget);
    expect(find.text('Add to calendar'), findsOneWidget);
  });

  testWidgets('turning on while offline queues it and retries later', (
    tester,
  ) async {
    handler = (_) => throw const SocketException('offline');
    await store.write(
      _account,
      const AllTripsFeedScope(),
      CalendarFeedSnapshot.empty,
    );
    await pumpScreen(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(stateLabel(tester), 'On');
    expect(find.textContaining('the feed will turn on'), findsOneWidget);
    expect(find.text('Add to calendar'), findsNothing);

    handler = (_) async => feed(_url);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text(_url), findsOneWidget);
    expect(requests.last.method, 'POST');
  });

  testWidgets('offline with nothing cached shows an explicit offline state', (
    tester,
  ) async {
    handler = (_) => throw const SocketException('offline');
    await pumpScreen(tester);

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a trip feed without share permission explains why', (
    tester,
  ) async {
    handler = (_) async =>
        http.Response(jsonEncode({'error': 'No permission'}), 403);
    await pumpScreen(tester, scope: const TripFeedScope('20'));

    expect(requests.single.url.path, '/api/trips/20/feed/token');
    expect(find.textContaining('manage sharing'), findsOneWidget);
  });
}
