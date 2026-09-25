/// Models for Trek's Vacay addon — the vacation-day planner
/// (`VacayController` under `/api/addons/vacay`). See docs/vacay.md.
///
/// Every model round-trips through [toJson] so it can be cached locally
/// (see `VacayLocalStore`). `fromJson` accepts both the server's response
/// shape and the cached shape, which are the same apart from the fields the
/// app drops (e.g. members' email addresses are never cached).
library;

/// Trek's fallback color for a plan member without one set.
const String vacayDefaultColor = '#6366f1';

/// A plan-level holiday calendar (`vacay_holiday_calendars`), e.g. a
/// country's public holidays or a region's school holidays.
class VacayHolidayCalendar {
  const VacayHolidayCalendar({
    required this.id,
    required this.type,
    required this.region,
    required this.label,
    required this.color,
  });

  factory VacayHolidayCalendar.fromJson(Map<String, dynamic> json) {
    return VacayHolidayCalendar(
      id: _asInt(json['id']),
      type: json['type'] as String? ?? 'public_holiday',
      region: json['region'] as String? ?? '',
      label: json['label'] as String?,
      color: json['color'] as String? ?? vacayDefaultColor,
    );
  }

  final int id;

  /// `public_holiday` or `school_holiday`.
  final String type;

  /// A region code such as `DE` or `DE-BY`.
  final String region;
  final String? label;
  final String color;

  bool get isSchoolHoliday => type == 'school_holiday';

  /// [label] if set, otherwise the region code.
  String get displayName =>
      (label == null || label!.trim().isEmpty) ? region : label!;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'region': region,
    'label': label,
    'color': color,
  };
}

/// Plan-wide settings from `GET /plan`'s `plan` object.
class VacayPlanSettings {
  const VacayPlanSettings({
    required this.id,
    required this.ownerId,
    required this.blockWeekends,
    required this.weekendDays,
    required this.weekStart,
    required this.holidaysEnabled,
    required this.schoolHolidaysEnabled,
    required this.companyHolidaysEnabled,
    required this.carryOverEnabled,
    required this.holidayCalendars,
  });

  factory VacayPlanSettings.fromJson(Map<String, dynamic> json) {
    return VacayPlanSettings(
      id: _asInt(json['id']),
      ownerId: _asInt(json['owner_id']),
      blockWeekends: _asBool(json['block_weekends']),
      weekendDays: _parseWeekendDays(json['weekend_days']),
      weekStart: json['week_start'] is num
          ? (json['week_start'] as num).toInt()
          : 1,
      holidaysEnabled: _asBool(json['holidays_enabled']),
      schoolHolidaysEnabled: _asBool(json['school_holidays_enabled']),
      companyHolidaysEnabled: _asBool(json['company_holidays_enabled']),
      carryOverEnabled: _asBool(json['carry_over_enabled']),
      holidayCalendars: [
        for (final c in json['holiday_calendars'] as List? ?? const [])
          VacayHolidayCalendar.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final int ownerId;
  final bool blockWeekends;

  /// Weekdays treated as the weekend, `0` = Sunday … `6` = Saturday
  /// (JavaScript `getUTCDay()` numbering). Trek stores these as a
  /// comma-separated string and falls back to Saturday/Sunday when unset.
  final List<int> weekendDays;

  /// First day of the week in the calendar grid, same numbering.
  final int weekStart;
  final bool holidaysEnabled;
  final bool schoolHolidaysEnabled;
  final bool companyHolidaysEnabled;
  final bool carryOverEnabled;
  final List<VacayHolidayCalendar> holidayCalendars;

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'block_weekends': blockWeekends,
    'weekend_days': weekendDays.join(','),
    'week_start': weekStart,
    'holidays_enabled': holidaysEnabled,
    'school_holidays_enabled': schoolHolidaysEnabled,
    'company_holidays_enabled': companyHolidaysEnabled,
    'carry_over_enabled': carryOverEnabled,
    'holiday_calendars': [for (final c in holidayCalendars) c.toJson()],
  };
}

/// A member of the active plan (the owner plus accepted members).
class VacayPlanUser {
  const VacayPlanUser({
    required this.id,
    required this.username,
    required this.color,
  });

  factory VacayPlanUser.fromJson(Map<String, dynamic> json) {
    return VacayPlanUser(
      id: _asInt(json['id']),
      username: json['username'] as String? ?? '',
      color: json['color'] as String? ?? vacayDefaultColor,
    );
  }

  final int id;
  final String username;
  final String color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'color': color,
  };
}

/// The plan overview: `GET /plan` plus `GET /years`.
class VacayPlan {
  const VacayPlan({
    required this.settings,
    required this.users,
    required this.isOwner,
    required this.pendingInviteCount,
    required this.incomingInviteCount,
    required this.years,
  });

  /// Combines the `GET /plan` body with the `years` list from
  /// `GET /years`.
  factory VacayPlan.fromJson(Map<String, dynamic> plan, List<dynamic> years) {
    return VacayPlan(
      settings: VacayPlanSettings.fromJson(
        plan['plan'] as Map<String, dynamic>? ?? const {},
      ),
      users: [
        for (final u in plan['users'] as List? ?? const [])
          VacayPlanUser.fromJson(u as Map<String, dynamic>),
      ],
      isOwner: _asBool(plan['isOwner']),
      pendingInviteCount: _countOf(plan['pendingInvites']),
      incomingInviteCount: _countOf(plan['incomingInvites']),
      years: [for (final y in years) _asInt(y)]..sort(),
    );
  }

  factory VacayPlan.fromCacheJson(Map<String, dynamic> json) {
    return VacayPlan(
      settings: VacayPlanSettings.fromJson(
        json['plan'] as Map<String, dynamic>,
      ),
      users: [
        for (final u in json['users'] as List)
          VacayPlanUser.fromJson(u as Map<String, dynamic>),
      ],
      isOwner: _asBool(json['isOwner']),
      pendingInviteCount: _asInt(json['pendingInviteCount']),
      incomingInviteCount: _asInt(json['incomingInviteCount']),
      years: [for (final y in json['years'] as List) _asInt(y)],
    );
  }

  final VacayPlanSettings settings;
  final List<VacayPlanUser> users;
  final bool isOwner;

  /// Invites this plan has sent that haven't been answered.
  final int pendingInviteCount;

  /// Invites from other plans to the signed-in user.
  final int incomingInviteCount;

  /// Tracked years, ascending.
  final List<int> years;

  /// Whether other users have joined the plan (Trek's `isFused`).
  bool get isShared => users.length > 1;

  /// The year to show first: the current calendar year if it's tracked,
  /// otherwise the latest tracked year before it, otherwise the earliest
  /// tracked year. `null` if no years are tracked.
  int? defaultYear(DateTime today) {
    if (years.isEmpty) return null;
    if (years.contains(today.year)) return today.year;
    final past = years.where((y) => y < today.year);
    return past.isNotEmpty ? past.last : years.first;
  }

  Map<String, dynamic> toJson() => {
    'plan': settings.toJson(),
    'users': [for (final u in users) u.toJson()],
    'isOwner': isOwner,
    'pendingInviteCount': pendingInviteCount,
    'incomingInviteCount': incomingInviteCount,
    'years': years,
  };
}

/// One plan member's allowance for a year (`GET /stats/:year`).
class VacayUserStats {
  const VacayUserStats({
    required this.userId,
    required this.personName,
    required this.personColor,
    required this.vacationDays,
    required this.carriedOver,
    required this.totalAvailable,
    required this.used,
    required this.remaining,
    required this.compUsed,
    required this.windowStart,
    required this.windowEnd,
  });

  factory VacayUserStats.fromJson(Map<String, dynamic> json) {
    return VacayUserStats(
      userId: _asInt(json['user_id']),
      personName: json['person_name'] as String? ?? '',
      personColor: json['person_color'] as String? ?? vacayDefaultColor,
      vacationDays: _asDouble(json['vacation_days']),
      carriedOver: _asDouble(json['carried_over']),
      totalAvailable: _asDouble(json['total_available']),
      used: _asDouble(json['used']),
      remaining: _asDouble(json['remaining']),
      compUsed: _asDouble(json['comp_used']),
      windowStart: json['window_start'] as String?,
      windowEnd: json['window_end'] as String?,
    );
  }

  final int userId;
  final String personName;
  final String personColor;

  /// The year's entitlement.
  final double vacationDays;

  /// Days carried over from the previous period (0 when carry-over is off).
  final double carriedOver;

  /// [vacationDays] + [carriedOver].
  final double totalAvailable;

  /// Vacation days booked in the period; half days count as 0.5 and
  /// comp/flex days don't count.
  final double used;

  /// [totalAvailable] − [used]; negative when overbooked.
  final double remaining;

  /// Comp/flex days booked in the period (free — not deducted).
  final double compUsed;

  /// The leave-year window the numbers cover, `[windowStart, windowEnd)`
  /// as `YYYY-MM-DD`. Jan 1 – Jan 1 for a calendar year; shifted for a
  /// fiscal or anniversary year.
  final String? windowStart;
  final String? windowEnd;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'person_name': personName,
    'person_color': personColor,
    'vacation_days': vacationDays,
    'carried_over': carriedOver,
    'total_available': totalAvailable,
    'used': used,
    'remaining': remaining,
    'comp_used': compUsed,
    'window_start': windowStart,
    'window_end': windowEnd,
  };
}

enum VacayEntryKind {
  vacation,

  /// Comp/flex time — free, not deducted from the allowance.
  comp;

  static VacayEntryKind parse(Object? value) =>
      value == 'comp' ? VacayEntryKind.comp : VacayEntryKind.vacation;
}

/// One booked day off (`vacay_entries`).
class VacayEntry {
  const VacayEntry({
    required this.id,
    required this.userId,
    required this.date,
    required this.fraction,
    required this.kind,
    required this.note,
    required this.personName,
    required this.personColor,
  });

  factory VacayEntry.fromJson(Map<String, dynamic> json) {
    return VacayEntry(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      date: json['date'] as String,
      fraction: _asDouble(json['fraction'], fallback: 1),
      kind: VacayEntryKind.parse(json['kind']),
      note: json['note'] as String? ?? '',
      personName: json['person_name'] as String? ?? '',
      personColor: json['person_color'] as String? ?? vacayDefaultColor,
    );
  }

  final int id;
  final int userId;

  /// `YYYY-MM-DD`.
  final String date;

  /// `1` for a full day, `0.5` for a half day.
  final double fraction;
  final VacayEntryKind kind;
  final String note;
  final String personName;
  final String personColor;

  bool get isHalfDay => fraction == 0.5;

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'date': date,
    'fraction': fraction,
    'kind': kind.name,
    'note': note,
    'person_name': personName,
    'person_color': personColor,
  };
}

/// A plan-wide company holiday (`vacay_company_holidays`).
class VacayCompanyHoliday {
  const VacayCompanyHoliday({required this.date, required this.note});

  factory VacayCompanyHoliday.fromJson(Map<String, dynamic> json) {
    return VacayCompanyHoliday(
      date: json['date'] as String,
      note: json['note'] as String? ?? '',
    );
  }

  /// `YYYY-MM-DD`.
  final String date;
  final String note;

  Map<String, dynamic> toJson() => {'date': date, 'note': note};
}

/// Everything shown for one tracked year: `GET /stats/:year` plus
/// `GET /entries/:year`.
class VacayYear {
  const VacayYear({
    required this.year,
    required this.stats,
    required this.entries,
    required this.companyHolidays,
  });

  /// Combines the `stats` list from `GET /stats/:year` with the
  /// `{ entries, companyHolidays }` body of `GET /entries/:year`.
  factory VacayYear.fromJson(
    int year,
    List<dynamic> stats,
    Map<String, dynamic> entries,
  ) {
    return VacayYear(
      year: year,
      stats: [
        for (final s in stats)
          VacayUserStats.fromJson(s as Map<String, dynamic>),
      ],
      entries: [
        for (final e in entries['entries'] as List? ?? const [])
          VacayEntry.fromJson(e as Map<String, dynamic>),
      ]..sort((a, b) => a.date.compareTo(b.date)),
      companyHolidays: [
        for (final h in entries['companyHolidays'] as List? ?? const [])
          VacayCompanyHoliday.fromJson(h as Map<String, dynamic>),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  factory VacayYear.fromCacheJson(Map<String, dynamic> json) {
    return VacayYear.fromJson(
      _asInt(json['year']),
      json['stats'] as List,
      json['entries'] as Map<String, dynamic>,
    );
  }

  final int year;
  final List<VacayUserStats> stats;

  /// Sorted by date.
  final List<VacayEntry> entries;

  /// Sorted by date.
  final List<VacayCompanyHoliday> companyHolidays;

  bool get isEmpty => entries.isEmpty && companyHolidays.isEmpty;

  Map<String, dynamic> toJson() => {
    'year': year,
    'stats': [for (final s in stats) s.toJson()],
    'entries': {
      'entries': [for (final e in entries) e.toJson()],
      'companyHolidays': [for (final h in companyHolidays) h.toJson()],
    },
  };
}

/// A cached value plus when it was fetched, so screens can say how old an
/// offline copy is.
class CachedVacay<T> {
  const CachedVacay({required this.value, required this.fetchedAt});

  final T value;
  final DateTime fetchedAt;
}

/// Formats a day count the way Trek does: whole numbers without a decimal,
/// half days as `.5`.
String formatVacayDays(double days) =>
    days == days.roundToDouble() ? '${days.toInt()}' : '$days';

int _asInt(Object? value) => value is num ? value.toInt() : 0;

double _asDouble(Object? value, {double fallback = 0}) =>
    value is num ? value.toDouble() : fallback;

/// Trek serializes some flags as booleans and stores others as 0/1.
bool _asBool(Object? value) => value == true || (value is num && value != 0);

int _countOf(Object? value) => value is List ? value.length : 0;

List<int> _parseWeekendDays(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    final days = [
      for (final part in value.split(',')) ?int.tryParse(part.trim()),
    ];
    if (days.isNotEmpty) return days;
  }
  return const [0, 6];
}
