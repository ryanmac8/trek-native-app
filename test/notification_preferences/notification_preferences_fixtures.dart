import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A user-scope matrix shaped like Trek's `getPreferencesMatrix(…, 'user')`
/// response: in-app plus email and webhook (webhook active but not
/// configured by this user), ntfy switched off by the admin, and one
/// plugin channel. `synology_session_cleared` is in-app only.
Map<String, dynamic> matrixJson({
  Map<String, Map<String, bool>> preferences = const {},
}) {
  const events = [
    'trip_invite',
    'booking_change',
    'collab_message',
    'synology_session_cleared',
  ];
  const external = ['email', 'webhook', 'ntfy', 'plugin:matrix'];
  final combos = {
    for (final e in events)
      e: ['inapp', if (e != 'synology_session_cleared') ...external],
  };
  return {
    'preferences': {
      for (final e in events)
        e: {for (final c in combos[e]!) c: preferences[e]?[c] ?? true},
    },
    'channels': [
      {
        'id': 'inapp',
        'source': 'builtin',
        'labelKey': 'settings.notificationPreferences.inapp',
        'active': true,
        'configured': true,
      },
      {
        'id': 'email',
        'source': 'builtin',
        'labelKey': 'settings.notificationPreferences.email',
        'active': true,
        'configured': true,
      },
      {
        'id': 'webhook',
        'source': 'builtin',
        'labelKey': 'settings.notificationPreferences.webhook',
        'active': true,
        'configured': false,
      },
      {
        'id': 'ntfy',
        'source': 'builtin',
        'labelKey': 'settings.notificationPreferences.ntfy',
        'active': false,
        'configured': false,
      },
      {
        'id': 'plugin:matrix',
        'source': 'plugin',
        'label': 'Matrix chat',
        'settingsPath': '/settings/plugins/matrix',
        'active': true,
        'configured': true,
      },
    ],
    'event_types': events,
    'implemented_combos': combos,
    'defaults': {'ntfyServer': null},
  };
}

/// A fake Trek server for the preferences endpoints: keeps the opt-out
/// cells a PUT writes (per cell, like the real service) and serves them
/// back as a full matrix. Set [offline] to fail every request the way a
/// dead network does, or [putStatus] to reject PUTs.
class FakePreferencesServer {
  bool offline = false;
  int putStatus = 200;
  final stored = <String, Map<String, bool>>{};
  final requests = <http.Request>[];

  /// Completes a PUT only when [putGate] completes, if set — lets a test
  /// change things locally while a request is in flight.
  Future<void>? putGate;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('Network is unreachable');
    if (request.method == 'PUT') {
      if (putGate != null) await putGate;
      if (putStatus != 200) {
        return http.Response(jsonEncode({'error': 'Rejected'}), putStatus);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      body.forEach((event, cells) {
        (cells as Map<String, dynamic>).forEach((channel, enabled) {
          stored.putIfAbsent(event, () => {})[channel] = enabled as bool;
        });
      });
    }
    return http.Response(jsonEncode(matrixJson(preferences: stored)), 200);
  });

  List<http.Request> get puts =>
      requests.where((r) => r.method == 'PUT').toList();
}
