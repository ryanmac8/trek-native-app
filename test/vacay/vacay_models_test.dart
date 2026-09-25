import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trek/vacay/vacay_models.dart';

import 'vacay_fixtures.dart';

void main() {
  group('VacayPlan', () {
    test('parses GET /plan + GET /years', () {
      final plan = VacayPlan.fromJson(planJson(), yearsJson()['years'] as List);

      expect(plan.settings.id, 3);
      expect(plan.settings.blockWeekends, isTrue);
      expect(plan.settings.weekendDays, [0, 6]);
      expect(plan.settings.carryOverEnabled, isTrue);
      expect(
        plan.settings.holidayCalendars.single.displayName,
        'NZ Public Holidays',
      );
      expect(plan.users.map((u) => u.username), ['ryan', 'sam']);
      expect(plan.isShared, isTrue);
      expect(plan.isOwner, isTrue);
      expect(plan.pendingInviteCount, 1);
      expect(plan.incomingInviteCount, 0);
      expect(plan.years, [2025, 2026]);
    });

    test('accepts 0/1 flags and falls back to Sat/Sun weekends', () {
      final json = planJson();
      (json['plan'] as Map<String, dynamic>)
        ..['block_weekends'] = 1
        ..['carry_over_enabled'] = 0
        ..['weekend_days'] = null
        ..['week_start'] = null;

      final settings = VacayPlan.fromJson(json, const []).settings;

      expect(settings.blockWeekends, isTrue);
      expect(settings.carryOverEnabled, isFalse);
      expect(settings.weekendDays, [0, 6]);
      expect(settings.weekStart, 1);
    });

    test('a calendar without a label is named by its region', () {
      final calendar = VacayHolidayCalendar.fromJson({
        'id': 1,
        'type': 'school_holiday',
        'region': 'DE-BY',
        'label': null,
        'color': '#fff',
      });
      expect(calendar.displayName, 'DE-BY');
      expect(calendar.isSchoolHoliday, isTrue);
    });

    test('round-trips through the cache without members\' emails', () {
      final plan = VacayPlan.fromJson(planJson(), [2026, 2025]);

      final encoded = jsonEncode(plan.toJson());
      final restored = VacayPlan.fromCacheJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(encoded, isNot(contains('@example.com')));
      expect(restored.years, [2025, 2026]);
      expect(restored.users.last.color, '#ec4899');
      expect(restored.pendingInviteCount, 1);
      expect(restored.settings.holidayCalendars.single.region, 'NZ');
      expect(restored.settings.blockWeekends, isTrue);
    });

    test('defaultYear prefers this year, then the latest past year', () {
      VacayPlan withYears(List<int> years) =>
          VacayPlan.fromJson(planJson(), years);

      expect(
        withYears([2025, 2026, 2027]).defaultYear(DateTime(2026, 5)),
        2026,
      );
      expect(withYears([2024, 2025]).defaultYear(DateTime(2026, 5)), 2025);
      expect(withYears([2027, 2028]).defaultYear(DateTime(2026, 5)), 2027);
      expect(withYears([]).defaultYear(DateTime(2026, 5)), isNull);
    });
  });

  group('VacayYear', () {
    test('parses stats and entries, sorted by date', () {
      final year = VacayYear.fromJson(
        2026,
        statsJson()['stats'] as List,
        entriesJson(),
      );

      final ryan = year.stats.first;
      expect(ryan.used, 4.5);
      expect(ryan.remaining, 23.5);
      expect(ryan.carriedOver, 3);
      expect(ryan.compUsed, 1);
      expect(year.stats.last.windowStart, '2026-04-06');

      expect(year.entries.map((e) => e.date), ['2026-03-02', '2026-03-09']);
      expect(year.entries.first.isHalfDay, isTrue);
      expect(year.entries.first.kind, VacayEntryKind.vacation);
      expect(year.entries.last.kind, VacayEntryKind.comp);
      expect(year.companyHolidays.single.note, 'Office closed');
      expect(year.isEmpty, isFalse);
    });

    test('entries predating fraction/kind read as full vacation days', () {
      final entry = VacayEntry.fromJson({
        'id': 1,
        'user_id': 1,
        'date': '2026-01-05',
        'note': '',
      });
      expect(entry.fraction, 1);
      expect(entry.kind, VacayEntryKind.vacation);
      expect(entry.personColor, vacayDefaultColor);
    });

    test('round-trips through the cache', () {
      final year = VacayYear.fromJson(
        2026,
        statsJson()['stats'] as List,
        entriesJson(),
      );

      final restored = VacayYear.fromCacheJson(
        jsonDecode(jsonEncode(year.toJson())) as Map<String, dynamic>,
      );

      expect(restored.year, 2026);
      expect(restored.stats.last.remaining, -2);
      expect(restored.entries.first.isHalfDay, isTrue);
      expect(restored.entries.last.kind, VacayEntryKind.comp);
      expect(restored.companyHolidays.single.date, '2026-12-24');
    });
  });

  test('formatVacayDays drops the decimal for whole days', () {
    expect(formatVacayDays(3), '3');
    expect(formatVacayDays(2.5), '2.5');
    expect(formatVacayDays(-2), '-2');
  });
}
