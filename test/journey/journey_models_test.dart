import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trek/journey/journey_models.dart';

import 'journey_fixtures.dart';

void main() {
  group('JourneyList', () {
    test('parses listJourneys rows', () {
      final list = JourneyList.fromJson(journeysJson());

      expect(list.journeys, hasLength(2));
      final first = list.journeys.first;
      expect(first.id, 7);
      expect(first.ownerId, 1);
      expect(first.title, 'South Island loop');
      expect(first.subtitle, 'Two weeks in a campervan');
      expect(first.status, JourneyStatus.active);
      expect(first.entryCount, 3);
      expect(first.photoCount, 1);
      expect(first.placeCount, 2);
      expect(first.tripDateMin, '2026-02-01');
      expect(first.tripDateMax, '2026-02-14');
      expect(first.updatedAt, 1770000000000);

      final second = list.journeys.last;
      expect(second.subtitle, isNull, reason: 'empty string reads as null');
      expect(second.status, JourneyStatus.completed);
      expect(second.coverGradient, startsWith('linear-gradient'));
      expect(second.tripDateMin, isNull);
    });

    test('an unknown status falls back to active', () {
      final json = journeysJson();
      (json['journeys'] as List).first['status'] = 'something-new';
      expect(
        JourneyList.fromJson(json).journeys.first.status,
        JourneyStatus.active,
      );
    });

    test('round-trips through the cache JSON', () {
      final list = JourneyList.fromJson(journeysJson());
      final restored = JourneyList.fromJson(
        jsonDecode(jsonEncode(list.toJson())) as Map<String, dynamic>,
      );
      expect(restored.journeys.map((j) => j.title), [
        'South Island loop',
        'Lisbon weekend',
      ]);
      expect(restored.journeys.last.status, JourneyStatus.completed);
    });
  });

  group('JourneyDetail', () {
    test('parses getJourneyFull', () {
      final journey = JourneyDetail.fromJson(journeyJson());

      expect(journey.id, 7);
      expect(journey.myRole, JourneyRole.owner);
      expect(journey.statEntries, 1);
      expect(journey.statPhotos, 1);
      expect(journey.statPlaces, 3);
      expect(journey.hideSkeletons, isFalse);

      expect(journey.trips.single.tripId, 20);
      expect(journey.trips.single.placeCount, 12);
      expect(journey.contributors.map((c) => c.role), [
        JourneyRole.owner,
        JourneyRole.editor,
      ]);

      final entry = journey.entries.first;
      expect(entry.type, JourneyEntryType.entry);
      expect(entry.entryTime, '14:30');
      expect(entry.tags, ['roadtrip', 'coast']);
      expect(entry.pros, ['Easy pickup']);
      expect(entry.cons, ['Jet lag']);
      expect(entry.photoCount, 1);

      expect(journey.entries[1].type, JourneyEntryType.checkin);
      expect(journey.entries[1].pros, isEmpty);
      expect(journey.entries[2].type, JourneyEntryType.skeleton);
      expect(journey.entries[2].sourceTripName, 'New Zealand');
    });

    test('accepts hide_skeletons as 0/1 and drops skeletons when set', () {
      final json = journeyJson()..['hide_skeletons'] = 1;
      final journey = JourneyDetail.fromJson(json);

      expect(journey.hideSkeletons, isTrue);
      expect(journey.entries, hasLength(3));
      expect(journey.visibleEntries.map((e) => e.id), [101, 102]);
    });

    test('keeps skeletons visible by default', () {
      final journey = JourneyDetail.fromJson(journeyJson());
      expect(journey.visibleEntries, hasLength(3));
    });

    test('round-trips through the cache JSON without photos or avatars', () {
      final journey = JourneyDetail.fromJson(journeyJson());
      final encoded = jsonEncode(journey.toJson());

      expect(encoded, isNot(contains('avatar')));
      expect(encoded, isNot(contains('journey/a.jpg')));

      final restored = JourneyDetail.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(restored.entries.first.photoCount, 1);
      expect(restored.entries.first.pros, ['Easy pickup']);
      expect(restored.entries[1].pros, isEmpty);
      expect(restored.contributors.last.username, 'sam');
      expect(restored.myRole, JourneyRole.owner);
      expect(restored.statPlaces, 3);
    });

    test('a missing my_role reads as null', () {
      final json = journeyJson()..['my_role'] = null;
      expect(JourneyDetail.fromJson(json).myRole, isNull);
    });
  });
}
