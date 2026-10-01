import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/calendar_feed/calendar_feed.dart';
import 'package:trek/calendar_feed/calendar_feed_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> values;

  setUp(() {
    values = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final key = call.arguments['key'] as String;
          switch (call.method) {
            case 'read':
              return values[key];
            case 'write':
              values[key] = call.arguments['value'] as String;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const scope = TripFeedScope('20');

  test('round-trips a snapshot per account and feed', () async {
    final store = SecureCalendarFeedStore();
    await store.write(
      'https://a.example#1',
      scope,
      const CalendarFeedSnapshot(
        feedUrl: 'https://a.example/api/feed/trip/t.ics',
        pending: CalendarFeedAction.rotate,
      ),
    );

    final read = await store.read('https://a.example#1', scope);
    expect(read!.feedUrl, 'https://a.example/api/feed/trip/t.ics');
    expect(read.pending, CalendarFeedAction.rotate);
    expect(await store.read('https://a.example#2', scope), isNull);
    expect(
      await store.read('https://a.example#1', const AllTripsFeedScope()),
      isNull,
    );
  });

  test('treats a corrupt entry as missing', () async {
    final store = SecureCalendarFeedStore();
    await store.write('acct', scope, CalendarFeedSnapshot.empty);
    values.updateAll((_, _) => 'not json');
    expect(await store.read('acct', scope), isNull);
  });
}
