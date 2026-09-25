import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `GET /api/addons/vacay/plan` for a two-person shared plan, shaped like
/// `VacayService.getPlanData`.
Map<String, dynamic> planJson() => {
  'plan': {
    'id': 3,
    'owner_id': 1,
    'block_weekends': true,
    'holidays_enabled': true,
    'holidays_region': null,
    'school_holidays_enabled': false,
    'company_holidays_enabled': true,
    'carry_over_enabled': true,
    'weekend_days': '0,6',
    'week_start': 1,
    'holiday_calendars': [
      {
        'id': 7,
        'plan_id': 3,
        'type': 'public_holiday',
        'region': 'NZ',
        'label': 'NZ Public Holidays',
        'color': '#fecaca',
        'sort_order': 0,
      },
    ],
  },
  'users': [
    {
      'id': 1,
      'username': 'ryan',
      'email': 'ryan@example.com',
      'color': '#6366f1',
    },
    {
      'id': 2,
      'username': 'sam',
      'email': 'sam@example.com',
      'color': '#ec4899',
    },
  ],
  'pendingInvites': [
    {
      'id': 9,
      'user_id': 4,
      'username': 'alex',
      'email': 'alex@example.com',
      'created_at': '2026-09-01 10:00:00',
    },
  ],
  'incomingInvites': <dynamic>[],
  'isOwner': true,
  'isFused': true,
};

/// `GET /api/addons/vacay/years`.
Map<String, dynamic> yearsJson() => {
  'years': [2025, 2026],
};

/// `GET /api/addons/vacay/stats/2026`.
Map<String, dynamic> statsJson([int year = 2026]) => {
  'stats': [
    {
      'user_id': 1,
      'person_name': 'ryan',
      'person_color': '#6366f1',
      'year': year,
      'vacation_days': 25,
      'carried_over': 3,
      'total_available': 28,
      'used': 4.5,
      'remaining': 23.5,
      'comp_used': 1,
      'window_start': '$year-01-01',
      'window_end': '${year + 1}-01-01',
    },
    {
      'user_id': 2,
      'person_name': 'sam',
      'person_color': '#ec4899',
      'year': year,
      'vacation_days': 20,
      'carried_over': 0,
      'total_available': 20,
      'used': 22,
      'remaining': -2,
      'comp_used': 0,
      'window_start': '$year-04-06',
      'window_end': '${year + 1}-04-06',
    },
  ],
};

/// `GET /api/addons/vacay/entries/2026` — deliberately out of date order.
Map<String, dynamic> entriesJson([int year = 2026]) => {
  'entries': [
    {
      'id': 12,
      'plan_id': 3,
      'user_id': 2,
      'date': '$year-03-09',
      'note': '',
      'fraction': 1,
      'kind': 'comp',
      'person_name': 'sam',
      'person_color': '#ec4899',
    },
    {
      'id': 11,
      'plan_id': 3,
      'user_id': 1,
      'date': '$year-03-02',
      'note': '',
      'fraction': 0.5,
      'kind': 'vacation',
      'person_name': 'ryan',
      'person_color': '#6366f1',
    },
  ],
  'companyHolidays': [
    {'id': 5, 'plan_id': 3, 'date': '$year-12-24', 'note': 'Office closed'},
  ],
};

/// A fake Trek server for the four Vacay read endpoints: serves the
/// fixtures above, or fails the connection the way a dead network does
/// when [offline].
class FakeVacayServer {
  bool offline = false;
  int status = 200;
  Map<String, dynamic> plan = planJson();
  Map<String, dynamic> years = yearsJson();
  Map<String, dynamic> Function(int year) entries = entriesJson;
  final requests = <http.Request>[];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('Network is unreachable');
    if (status != 200) {
      return http.Response(jsonEncode({'error': 'boom'}), status);
    }
    final path = request.url.path.replaceFirst('/api/addons/vacay/', '');
    final segments = path.split('/');
    final body = switch (segments) {
      ['plan'] => plan,
      ['years'] => years,
      ['stats', final y] => statsJson(int.parse(y)),
      ['entries', final y] => entries(int.parse(y)),
      _ => null,
    };
    if (body == null) return http.Response('{"error":"Not found"}', 404);
    return http.Response(jsonEncode(body), 200);
  });
}
