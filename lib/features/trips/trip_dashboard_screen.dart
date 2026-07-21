import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../days/day.dart';
import '../../design/app_spacing.dart';
import '../../design/place_category_colors.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo sections the issue #2 nav structure calls for. Days (this
/// slice of issue #4) reads from real data; the rest are still placeholders
/// — none of those data models exist yet (issues #5–#9).
class TripDashboardScreen extends StatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripDashboardScreen> createState() => _TripDashboardScreenState();
}

class _TripDashboardScreenState extends State<TripDashboardScreen> {
  int _tabIndex = 0;

  static const _tabs = [
    (label: 'Days', icon: Icons.calendar_today),
    (label: 'Places', icon: Icons.place),
    (label: 'Budget', icon: Icons.attach_money),
    (label: 'Packing', icon: Icons.checklist),
    (label: 'Todos', icon: Icons.task_alt),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip ${widget.tripId}')),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _DaysTab(tripId: widget.tripId),
          const _PlacesPreviewTab(),
          const _ComingSoonTab(label: 'Budget'),
          const _ComingSoonTab(label: 'Packing'),
          const _ComingSoonTab(label: 'Todos'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$label — coming soon',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

/// The Days tab: per docs/offline-first.md, the local cache
/// ([DaysRepository.cachedDays]) is the source of truth for what's shown —
/// this paints from it immediately, then refreshes from the network in the
/// background. A [NetworkException] only surfaces as an explicit offline
/// state when there's nothing cached yet; if days are already on screen, a
/// failed background refresh just leaves them be.
class _DaysTab extends ConsumerStatefulWidget {
  const _DaysTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_DaysTab> createState() => _DaysTabState();
}

class _DaysTabState extends ConsumerState<_DaysTab> {
  List<Day>? _days;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(daysRepositoryProvider);
    final cached = await repository.cachedDays(widget.tripId);
    if (!mounted) return;
    setState(() {
      _days = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(daysRepositoryProvider);
    try {
      final refreshed = await repository.refreshDays(widget.tripId);
      if (!mounted) return;
      setState(() {
        _days = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_days == null || _days!.isEmpty) _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;

    if (days == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (days.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message:
              "You're offline. Days will load once you're "
              'back online.',
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load days.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.calendar_today,
        message: 'No days yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: days.length,
        itemBuilder: (context, index) {
          final day = days[index];
          return AppListRow(
            title: (day.title != null && day.title!.isNotEmpty)
                ? day.title!
                : 'Day ${day.dayNumber}',
            subtitle: _subtitle(day),
            trailing: Text(
              day.assignmentCount == 1
                  ? '1 place'
                  : '${day.assignmentCount} places',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    );
  }

  String? _subtitle(Day day) {
    final date = day.date;
    final dateLabel = date == null
        ? null
        : '${date.month}/${date.day}/${date.year}';
    final notes = day.notes;
    if (dateLabel != null && notes != null && notes.isNotEmpty) {
      return '$dateLabel · $notes';
    }
    return dateLabel ?? notes;
  }
}

/// The Places tab has no data yet, but doubles as a visual check of the
/// category color/icon tokens ([PlaceCategory]) against Trek's real
/// category list.
class _PlacesPreviewTab extends StatelessWidget {
  const _PlacesPreviewTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Places — coming soon',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final category in PlaceCategory.values)
              Chip(
                avatar: CircleAvatar(
                  backgroundColor: category.color,
                  child: Text(
                    category.icon,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                label: Text(category.label),
              ),
          ],
        ),
      ],
    );
  }
}
