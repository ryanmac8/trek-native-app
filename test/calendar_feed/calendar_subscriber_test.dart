import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/calendar_feed/calendar_subscriber.dart';

const _url = 'https://trek.example.com/api/feed/trip/abc.ics';

void main() {
  test('webcalUri swaps the scheme and keeps host, port and path', () {
    expect(
      webcalUri(_url).toString(),
      'webcal://trek.example.com/api/feed/trip/abc.ics',
    );
    expect(
      webcalUri('http://192.168.1.5:3000/api/feed/user/t.ics').toString(),
      'webcal://192.168.1.5:3000/api/feed/user/t.ics',
    );
  });

  test('googleCalendarSubscribeUri passes the webcal URL as cid', () {
    final uri = googleCalendarSubscribeUri(_url);
    expect(uri.host, 'calendar.google.com');
    expect(uri.path, '/calendar/render');
    expect(
      uri.queryParameters['cid'],
      'webcal://trek.example.com/api/feed/trip/abc.ics',
    );
  });

  test('opens the webcal URL first', () async {
    final launched = <Uri>[];
    final subscriber = UrlLauncherCalendarSubscriber(
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
      platform: TargetPlatform.android,
    );

    expect(await subscriber.subscribe(_url), isTrue);
    expect(launched.single.scheme, 'webcal');
  });

  test('falls back to Google Calendar on Android', () async {
    final launched = <Uri>[];
    final subscriber = UrlLauncherCalendarSubscriber(
      launch: (uri) async {
        launched.add(uri);
        return uri.scheme == 'https';
      },
      platform: TargetPlatform.android,
    );

    expect(await subscriber.subscribe(_url), isTrue);
    expect(launched.map((u) => u.scheme), ['webcal', 'https']);
  });

  test('has no fallback on iOS', () async {
    final launched = <Uri>[];
    final subscriber = UrlLauncherCalendarSubscriber(
      launch: (uri) async {
        launched.add(uri);
        return false;
      },
      platform: TargetPlatform.iOS,
    );

    expect(await subscriber.subscribe(_url), isFalse);
    expect(launched, hasLength(1));
  });

  test('treats a launcher exception as not launched', () async {
    final subscriber = UrlLauncherCalendarSubscriber(
      launch: (uri) async =>
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      platform: TargetPlatform.android,
    );
    expect(await subscriber.subscribe(_url), isFalse);
  });
}
