import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/journey/journey_local_store.dart';
import 'package:trek/journey/journey_models.dart';

/// `GET /api/journeys`, shaped like `JourneyDomainService.listJourneys`.
Map<String, dynamic> journeysJson() => {
  'journeys': [
    {
      'id': 7,
      'user_id': 1,
      'title': 'South Island loop',
      'subtitle': 'Two weeks in a campervan',
      'cover_gradient': null,
      'cover_image': 'covers/nz.jpg',
      'status': 'active',
      'show_trip_tracks': 0,
      'created_at': 1767225600000,
      'updated_at': 1770000000000,
      'entry_count': 3,
      'photo_count': 1,
      'place_count': 2,
      'trip_date_min': '2026-02-01',
      'trip_date_max': '2026-02-14',
    },
    {
      'id': 9,
      'user_id': 2,
      'title': 'Lisbon weekend',
      'subtitle': '',
      'cover_gradient': 'linear-gradient(135deg, #f00, #00f)',
      'cover_image': null,
      'status': 'completed',
      'created_at': 1760000000000,
      'updated_at': 1760000000000,
      'entry_count': 1,
      'photo_count': 0,
      'place_count': 1,
      'trip_date_min': null,
      'trip_date_max': null,
    },
  ],
};

/// `GET /api/journeys/:id`, shaped like `JourneyDomainService.getJourneyFull`.
Map<String, dynamic> journeyJson({int id = 7, bool hideSkeletons = false}) => {
  'id': id,
  'user_id': 1,
  'title': 'South Island loop',
  'subtitle': 'Two weeks in a campervan',
  'cover_gradient': null,
  'cover_image': 'covers/nz.jpg',
  'status': 'active',
  'created_at': 1767225600000,
  'updated_at': 1770000000000,
  'entries': [
    {
      'id': 101,
      'journey_id': id,
      'source_trip_id': null,
      'author_id': 1,
      'type': 'entry',
      'title': 'Arrival in Christchurch',
      'story': 'Picked up the van and drove to the coast.',
      'entry_date': '2026-02-01',
      'entry_time': '14:30',
      'location_name': 'Christchurch',
      'location_lat': -43.53,
      'location_lng': 172.63,
      'mood': 'happy',
      'weather': 'sunny',
      'tags': ['roadtrip', 'coast'],
      'pros_cons': {
        'pros': ['Easy pickup'],
        'cons': ['Jet lag'],
      },
      'visibility': 'private',
      'sort_order': 0,
      'stats_excluded': false,
      'dismissed': false,
      'photos': [
        {'id': 1, 'entry_id': 101, 'photo_id': 5, 'file_path': 'journey/a.jpg'},
      ],
      'source_trip_name': null,
    },
    {
      'id': 102,
      'journey_id': id,
      'author_id': 1,
      'type': 'checkin',
      'title': null,
      'story': null,
      'entry_date': '2026-02-01',
      'entry_time': null,
      'location_name': 'Sumner Beach',
      'tags': [],
      'pros_cons': null,
      'visibility': 'private',
      'sort_order': 1,
      'photos': [],
      'source_trip_name': null,
    },
    {
      'id': 103,
      'journey_id': id,
      'source_trip_id': 20,
      'author_id': 1,
      'type': 'skeleton',
      'title': 'Lake Tekapo',
      'entry_date': '2026-02-03',
      'location_name': 'Lake Tekapo',
      'tags': [],
      'pros_cons': null,
      'visibility': 'private',
      'sort_order': 0,
      'photos': [],
      'source_trip_name': 'New Zealand',
    },
  ],
  'gallery': [
    {'id': 1, 'journey_id': id, 'photo_id': 5},
  ],
  'trips': [
    {
      'trip_id': 20,
      'added_at': 1767225600000,
      'title': 'New Zealand',
      'start_date': '2026-02-01',
      'end_date': '2026-02-14',
      'cover_image': null,
      'currency': 'NZD',
      'place_count': 12,
    },
  ],
  'contributors': [
    {
      'journey_id': id,
      'user_id': 1,
      'role': 'owner',
      'added_at': 1767225600000,
      'username': 'ryan',
      'avatar': null,
      'avatar_url': null,
    },
    {
      'journey_id': id,
      'user_id': 2,
      'role': 'editor',
      'added_at': 1767225600000,
      'username': 'sam',
      'avatar': 'a.png',
      'avatar_url': '/uploads/avatars/a.png',
    },
  ],
  'stats': {'entries': 1, 'photos': 1, 'places': 3},
  'hide_skeletons': hideSkeletons,
  'dismissed_count': 0,
  'my_role': 'owner',
};

/// A fake Trek server for `/api/journeys` behind `package:http/testing`.
class FakeJourneyServer {
  bool offline = false;
  bool addonDisabled = false;
  Map<String, dynamic> list = journeysJson();
  Map<String, dynamic>? Function(int id) journey = (id) =>
      id == 7 ? journeyJson() : null;
  final requests = <http.Request>[];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('Network is unreachable');
    if (addonDisabled) {
      return http.Response(
        jsonEncode({'error': 'Journey addon is not enabled'}),
        404,
      );
    }
    final segments = request.url.pathSegments;
    final body = switch (segments) {
      ['api', 'journeys'] => list,
      ['api', 'journeys', final id] => journey(int.parse(id)),
      _ => null,
    };
    if (body == null) {
      return http.Response(jsonEncode({'error': 'Journey not found'}), 404);
    }
    return http.Response(jsonEncode(body), 200);
  });
}

/// In-memory [JourneyLocalStore] — avoids the `shared_preferences`
/// platform channel in widget tests.
class MemoryJourneyLocalStore implements JourneyLocalStore {
  final _lists = <String, CachedJourney<JourneyList>>{};
  final _journeys = <String, CachedJourney<JourneyDetail>>{};

  @override
  Future<CachedJourney<JourneyList>?> readList(String scope) async =>
      _lists[scope];

  @override
  Future<void> writeList(String scope, CachedJourney<JourneyList> list) async =>
      _lists[scope] = list;

  @override
  Future<CachedJourney<JourneyDetail>?> readJourney(
    String scope,
    int id,
  ) async => _journeys['$scope/$id'];

  @override
  Future<void> writeJourney(
    String scope,
    CachedJourney<JourneyDetail> journey,
  ) async => _journeys['$scope/${journey.value.id}'] = journey;
}
