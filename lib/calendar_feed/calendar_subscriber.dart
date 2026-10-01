import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands a feed URL to the device's calendar as a subscription (a calendar
/// the OS re-fetches on its own), rather than a one-time `.ics` import.
abstract class CalendarSubscriber {
  /// Returns `false` when no installed app accepted the subscription.
  Future<bool> subscribe(String feedUrl);
}

/// The `webcal://` form of an `http(s)://` feed URL — the scheme iOS
/// Calendar (and most desktop calendar apps) treat as "subscribe".
Uri webcalUri(String feedUrl) => Uri.parse(feedUrl).replace(scheme: 'webcal');

/// Google Calendar's "add calendar by URL" link, for Android devices with no
/// `webcal://` handler installed. Google fetches the feed from its own
/// servers, so this only works for a publicly reachable Trek server.
Uri googleCalendarSubscribeUri(String feedUrl) => Uri.https(
  'calendar.google.com',
  '/calendar/render',
  {'cid': webcalUri(feedUrl).toString()},
);

class UrlLauncherCalendarSubscriber implements CalendarSubscriber {
  UrlLauncherCalendarSubscriber({
    Future<bool> Function(Uri uri)? launch,
    TargetPlatform? platform,
  }) : _launch = launch ?? _launchExternal,
       _platform = platform;

  final Future<bool> Function(Uri uri) _launch;
  final TargetPlatform? _platform;

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<bool> subscribe(String feedUrl) async {
    if (await _tryLaunch(webcalUri(feedUrl))) return true;
    if ((_platform ?? defaultTargetPlatform) == TargetPlatform.android) {
      return _tryLaunch(googleCalendarSubscribeUri(feedUrl));
    }
    return false;
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await _launch(uri);
    } on Exception {
      return false;
    }
  }
}
