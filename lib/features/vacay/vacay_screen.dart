import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../vacay/vacay_models.dart';

/// The Vacay plan overview (first slice of issue #19): a year switcher
/// over the plan's tracked years, each member's allowance for the selected
/// year, the booked days and company holidays, and the plan's settings.
/// Read-only.
///
/// Per docs/offline-first.md it reads through [VacayRepository]: the
/// last-known plan and year paint from the local cache first, and a failed
/// refresh keeps them on screen with an offline notice rather than blanking
/// or throwing. With nothing cached and no connection, an explicit offline
/// state with a retry is shown — for the whole screen, or just for a year
/// that was never loaded.
class VacayScreen extends ConsumerStatefulWidget {
  const VacayScreen({super.key, this.clock = DateTime.now});

  /// The current time, injectable for tests.
  final DateTime Function() clock;

  @override
  ConsumerState<VacayScreen> createState() => _VacayScreenState();
}

class _VacayScreenState extends ConsumerState<VacayScreen> {
  CachedVacay<VacayPlan>? _plan;
  bool _planStale = false;
  Object? _planError;
  bool _loading = true;

  int? _selectedYear;
  CachedVacay<VacayYear>? _year;
  bool _yearStale = false;
  Object? _yearError;
  bool _yearLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _planError = null;
    });

    final repository = ref.read(vacayRepositoryProvider);

    // Paint the cached plan (and its year) first so the screen isn't blank
    // while the refresh runs.
    final cached = await repository.cachedPlan();
    if (!mounted) return;
    if (cached != null && _plan == null) {
      final year = cached.value.defaultYear(widget.clock());
      final cachedYear = year == null
          ? null
          : await repository.cachedYear(year);
      if (!mounted) return;
      setState(() {
        _plan = cached;
        _planStale = true;
        _selectedYear = year;
        if (cachedYear != null) {
          _year = cachedYear;
          _yearStale = true;
        }
      });
    }

    try {
      final fresh = await repository.refreshPlan();
      if (!mounted) return;
      setState(() {
        _plan = fresh;
        _planStale = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_plan == null) {
          _planError = e;
        } else {
          _planStale = true;
        }
      });
    }

    final plan = _plan?.value;
    if (plan != null) {
      final selected = _selectedYear;
      final year = selected != null && plan.years.contains(selected)
          ? selected
          : plan.defaultYear(widget.clock());
      if (year != null) await _loadYear(year);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadYear(int year) async {
    setState(() {
      _selectedYear = year;
      _yearError = null;
      _yearLoading = true;
      if (_year?.value.year != year) {
        _year = null;
        _yearStale = false;
      }
    });

    final repository = ref.read(vacayRepositoryProvider);
    final cached = await repository.cachedYear(year);
    if (!mounted || _selectedYear != year) return;
    if (cached != null && _year == null) {
      setState(() {
        _year = cached;
        _yearStale = true;
      });
    }

    try {
      final fresh = await repository.refreshYear(year);
      if (!mounted || _selectedYear != year) return;
      setState(() {
        _year = fresh;
        _yearStale = false;
      });
    } catch (e) {
      if (!mounted || _selectedYear != year) return;
      setState(() {
        if (_year == null) {
          _yearError = e;
        } else {
          _yearStale = true;
        }
      });
    } finally {
      if (mounted && _selectedYear == year) {
        setState(() => _yearLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vacay')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cachedPlan = _plan;

    if (cachedPlan == null && _loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 40),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 120),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 200),
        ],
      );
    }

    if (cachedPlan == null) {
      final offline = _planError is NetworkException;
      return _Scrollable(
        child: EmptyState(
          icon: offline ? Icons.cloud_off : Icons.error_outline,
          message: offline
              ? "You're offline, and your Vacay plan hasn't been loaded yet."
              : "Couldn't load your Vacay plan.",
          action: FilledButton(onPressed: _load, child: const Text('Retry')),
        ),
      );
    }

    final plan = cachedPlan.value;
    if (plan.years.isEmpty) {
      return const _Scrollable(
        child: EmptyState(
          icon: Icons.beach_access,
          message: 'No years tracked yet.',
        ),
      );
    }

    final year = _year;
    final stale = (_planStale || (_yearStale && year != null)) && !_loading;
    final staleSince = [
      cachedPlan.fetchedAt,
      if (year != null && _yearStale) year.fetchedAt,
    ].reduce((a, b) => a.isBefore(b) ? a : b);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (stale) ...[
          _StaleBanner(fetchedAt: staleSince, onRetry: _load),
          const SizedBox(height: AppSpacing.md),
        ],
        if (plan.incomingInviteCount > 0) ...[
          _InviteNotice(count: plan.incomingInviteCount),
          const SizedBox(height: AppSpacing.md),
        ],
        _YearSelector(
          years: plan.years,
          selected: _selectedYear,
          onSelected: _loadYear,
        ),
        const SizedBox(height: AppSpacing.md),
        ..._buildYear(context, plan),
        const SizedBox(height: AppSpacing.md),
        _PlanSettingsCard(plan: plan),
      ],
    );
  }

  List<Widget> _buildYear(BuildContext context, VacayPlan plan) {
    final year = _year?.value;
    if (year == null && _yearLoading) {
      return const [
        SkeletonBox(height: 120),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 160),
      ];
    }
    if (year == null) {
      final offline = _yearError is NetworkException;
      return [
        AppCard(
          child: EmptyState(
            icon: offline ? Icons.cloud_off : Icons.error_outline,
            message: offline
                ? "You're offline, and $_selectedYear hasn't been loaded yet."
                : "Couldn't load $_selectedYear.",
            action: FilledButton(
              onPressed: () => _loadYear(_selectedYear!),
              child: const Text('Retry'),
            ),
          ),
        ),
      ];
    }
    return [
      for (final stats in year.stats) ...[
        _AllowanceCard(stats: stats, year: year.year),
        const SizedBox(height: AppSpacing.md),
      ],
      _DaysOffCard(year: year, showNames: plan.isShared),
    ];
  }
}

/// Keeps pull-to-refresh working on the non-list states.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: constraints.maxHeight, child: child),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.fetchedAt, required this.onRetry});

  final DateTime fetchedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final local = fetchedAt.toLocal();
    final date =
        '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Offline — showing your plan from $date.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _InviteNotice extends StatelessWidget {
  const _InviteNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.mail_outline),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count == 1
                  ? 'You have an invite to join another Vacay plan.'
                  : 'You have $count invites to join other Vacay plans.',
            ),
          ),
        ],
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.years,
    required this.selected,
    required this.onSelected,
  });

  final List<int> years;
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final year in years)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text('$year'),
                selected: year == selected,
                onSelected: (_) {
                  if (year != selected) onSelected(year);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AllowanceCard extends StatelessWidget {
  const _AllowanceCard({required this.stats, required this.year});

  final VacayUserStats stats;
  final int year;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = _parseColor(stats.personColor);
    final total = stats.totalAvailable;
    final overbooked = stats.remaining < 0;
    final details = [
      'Used ${formatVacayDays(stats.used)} of ${formatVacayDays(total)}',
      if (stats.carriedOver > 0)
        '${formatVacayDays(stats.carriedOver)} carried over',
      if (stats.compUsed > 0)
        '${formatVacayDays(stats.compUsed)} comp '
            '${stats.compUsed == 1 ? 'day' : 'days'}',
    ];
    final window = _windowLabel(stats, year);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ColorDot(color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(stats.personName, style: textTheme.titleMedium),
              ),
              Text(
                overbooked
                    ? '${formatVacayDays(-stats.remaining)} over'
                    : '${formatVacayDays(stats.remaining)} left',
                style: textTheme.titleMedium?.copyWith(
                  color: overbooked
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: total <= 0 ? 0 : (stats.used / total).clamp(0, 1),
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(details.join(' · '), style: textTheme.bodySmall),
          if (window != null) Text(window, style: textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Labels a leave year that isn't Jan–Dec (fiscal or anniversary).
  static String? _windowLabel(VacayUserStats stats, int year) {
    final start = DateTime.tryParse(stats.windowStart ?? '');
    final end = DateTime.tryParse(stats.windowEnd ?? '');
    if (start == null || end == null) return null;
    if (start == DateTime(year) && end == DateTime(year + 1)) return null;
    final last = end.subtract(const Duration(days: 1));
    return 'Leave year ${_shortDate(start)} – ${_shortDate(last)}';
  }
}

class _DaysOffCard extends StatelessWidget {
  const _DaysOffCard({required this.year, required this.showNames});

  final VacayYear year;
  final bool showNames;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (year.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.event_available),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('No days off booked in ${year.year}.')),
          ],
        ),
      );
    }

    // Merge entries and company holidays into one date-ordered list, then
    // group by month.
    final rows = <(String, Widget)>[
      for (final entry in year.entries)
        (entry.date, _EntryRow(entry: entry, showName: showNames)),
      for (final holiday in year.companyHolidays)
        (holiday.date, _CompanyHolidayRow(holiday: holiday)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    final children = <Widget>[];
    String? month;
    for (final (date, row) in rows) {
      final key = date.substring(0, 7);
      if (key != month) {
        month = key;
        final parsed = DateTime.parse('$key-01');
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: children.isEmpty ? 0 : AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              '${_monthNames[parsed.month - 1]} ${parsed.year}',
              style: textTheme.titleSmall,
            ),
          ),
        );
      }
      children.add(row);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.showName});

  final VacayEntry entry;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final tags = [
      if (entry.isHalfDay) 'Half day',
      if (entry.kind == VacayEntryKind.comp) 'Comp',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(_dayLabel(entry.date))),
          _ColorDot(color: _parseColor(entry.personColor)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              showName ? entry.personName : 'Day off',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (tags.isNotEmpty)
            Text(
              tags.join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _CompanyHolidayRow extends StatelessWidget {
  const _CompanyHolidayRow({required this.holiday});

  final VacayCompanyHoliday holiday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(_dayLabel(holiday.date))),
          const Icon(Icons.business, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              holiday.note.isEmpty
                  ? 'Company holiday'
                  : 'Company holiday · ${holiday.note}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSettingsCard extends StatelessWidget {
  const _PlanSettingsCard({required this.plan});

  final VacayPlan plan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final settings = plan.settings;
    final calendars = settings.holidaysEnabled
        ? settings.holidayCalendars
        : const <VacayHolidayCalendar>[];
    final rows = <(IconData, String, String)>[
      (
        Icons.weekend_outlined,
        'Weekends blocked',
        settings.blockWeekends
            ? settings.weekendDays.map((d) => _weekdayNames[d % 7]).join(', ')
            : 'Off',
      ),
      (Icons.redo, 'Carry-over', settings.carryOverEnabled ? 'On' : 'Off'),
      (
        Icons.business,
        'Company holidays',
        settings.companyHolidaysEnabled ? 'On' : 'Off',
      ),
      (
        Icons.flag_outlined,
        'Holiday calendars',
        calendars.isEmpty
            ? 'None'
            : calendars.map((c) => c.displayName).join(', '),
      ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.isShared ? 'Shared plan' : 'Plan',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final user in plan.users)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ColorDot(color: _parseColor(user.color)),
                    const SizedBox(width: AppSpacing.xs),
                    Text(user.username),
                  ],
                ),
            ],
          ),
          if (plan.pendingInviteCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${plan.pendingInviteCount} pending '
                '${plan.pendingInviteCount == 1 ? 'invite' : 'invites'}',
                style: textTheme.bodySmall,
              ),
            ),
          const Divider(height: AppSpacing.lg),
          for (final (icon, label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(label)),
                  Flexible(child: Text(value, textAlign: TextAlign.end)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Indexed by Trek's weekday numbering (0 = Sunday).
const _weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// `YYYY-MM-DD` → e.g. `Mon 3`.
String _dayLabel(String date) {
  final parsed = DateTime.parse(date);
  return '${_weekdayNames[parsed.weekday % 7]} ${parsed.day}';
}

/// e.g. `Apr 6, 2026`.
String _shortDate(DateTime date) =>
    '${_monthNames[date.month - 1].substring(0, 3)} ${date.day}, ${date.year}';

/// Parses Trek's `#rrggbb` colors, falling back to its default indigo.
Color _parseColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (value == null || hex.length != 7) return const Color(0xFF6366F1);
  return Color(0xFF000000 | value);
}

String _two(int value) => value.toString().padLeft(2, '0');
