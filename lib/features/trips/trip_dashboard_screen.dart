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

/// A section of the trip dashboard's bottom nav. [key] is a stable
/// identifier persisted by [TripDashboardNavLayoutStore] — unlike [label],
/// it must never change once shipped, or a saved layout silently forgets
/// that tab.
enum _TripTab {
  days('days', 'Days', Icons.calendar_today),
  places('places', 'Places', Icons.place),
  budget('budget', 'Budget', Icons.attach_money),
  packing('packing', 'Packing', Icons.checklist),
  todos('todos', 'Todos', Icons.task_alt),
  book('book', 'Book', Icons.menu_book),
  lists('lists', 'Lists', Icons.format_list_bulleted),
  files('files', 'Files', Icons.folder),
  collab('collab', 'Collab', Icons.groups);

  const _TripTab(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;

  static _TripTab? fromKey(String? key) {
    if (key == null) return null;
    for (final tab in _TripTab.values) {
      if (tab.key == key) return tab;
    }
    return null;
  }
}

/// How many tabs the collapsed bar shows before the "more" toggle. The rest
/// live in the expandable overflow panel.
const _maxVisibleTabs = 4;

const _defaultVisibleTabs = [
  _TripTab.days,
  _TripTab.places,
  _TripTab.budget,
  _TripTab.packing,
];

/// Per-trip shell: a customizable bottom nav switching between the day/
/// place/budget/packing/todo/book/lists/files/collab sections the issue #2
/// nav structure calls for. Only 4 fit in the collapsed bar at once — the
/// trailing button opens an overflow panel with the rest, and any tab can
/// be dragged between the bar and that panel to customize which 4 show by
/// default (see [TripDashboardNavLayoutStore] for how that's persisted).
/// Days (issue #4) reads real data; the rest are still placeholders — none
/// of those data models exist yet (issues #5–#9, and Book/Lists/Files/
/// Collab aren't tracked issues yet either).
class TripDashboardScreen extends ConsumerStatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripDashboardScreen> createState() =>
      _TripDashboardScreenState();
}

class _TripDashboardScreenState extends ConsumerState<TripDashboardScreen> {
  _TripTab _selected = _TripTab.days;
  bool _expanded = false;

  /// Fixed-length (always [_maxVisibleTabs]) — a `null` entry is an empty
  /// slot, left that way after a tab was dragged out without a replacement
  /// dragged in.
  List<_TripTab?> _visibleSlots = List.of(_defaultVisibleTabs);

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final stored = await ref.read(tripDashboardNavLayoutStoreProvider).read();
    if (stored == null || !mounted) return;
    setState(() {
      _visibleSlots = List.generate(
        _maxVisibleTabs,
        (i) => i < stored.length ? _TripTab.fromKey(stored[i]) : null,
      );
    });
  }

  void _persistLayout() {
    ref
        .read(tripDashboardNavLayoutStoreProvider)
        .write(_visibleSlots.map((t) => t?.key).toList());
  }

  List<_TripTab> get _hiddenTabs =>
      _TripTab.values.where((t) => !_visibleSlots.contains(t)).toList();

  void _select(_TripTab tab) {
    setState(() {
      _selected = tab;
      _expanded = false;
    });
  }

  /// Drops [dragged] onto bar slot [targetIndex]. If [dragged] was already
  /// in another slot, that slot gets whatever [targetIndex] previously
  /// held (a swap); if it came from the overflow panel, the displaced tab
  /// (if any) simply falls back into the panel, since the panel's contents
  /// are just "every tab not currently in a slot."
  void _dropOntoSlot(int targetIndex, _TripTab dragged) {
    setState(() {
      final fromIndex = _visibleSlots.indexOf(dragged);
      final displaced = _visibleSlots[targetIndex];
      _visibleSlots[targetIndex] = dragged;
      if (fromIndex != -1 && fromIndex != targetIndex) {
        _visibleSlots[fromIndex] = displaced;
      }
    });
    _persistLayout();
  }

  /// Drops [dragged] onto the overflow panel — only meaningful when it came
  /// from a bar slot, which it then vacates.
  void _dropOntoPanel(_TripTab dragged) {
    final fromIndex = _visibleSlots.indexOf(dragged);
    if (fromIndex == -1) return;
    setState(() => _visibleSlots[fromIndex] = null);
    _persistLayout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip ${widget.tripId}')),
      body: IndexedStack(
        index: _TripTab.values.indexOf(_selected),
        children: [for (final tab in _TripTab.values) _bodyFor(tab)],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
                child: _expanded
                    ? _OverflowPanel(
                        key: const ValueKey('expanded'),
                        tabs: _hiddenTabs,
                        onSelect: _select,
                        onDropped: _dropOntoPanel,
                      )
                    : const SizedBox.shrink(key: ValueKey('collapsed')),
              ),
              _buildBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          for (var i = 0; i < _maxVisibleTabs; i++)
            Expanded(
              child: _BarSlot(
                tab: _visibleSlots[i],
                selected: _visibleSlots[i] == _selected,
                onSelect: _select,
                onDropped: (dragged) => _dropOntoSlot(i, dragged),
              ),
            ),
          SizedBox(
            width: 64,
            child: IconButton(
              tooltip: _expanded ? 'Close' : 'More',
              icon: Icon(_expanded ? Icons.close : Icons.menu),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyFor(_TripTab tab) {
    switch (tab) {
      case _TripTab.days:
        return _DaysTab(tripId: widget.tripId);
      case _TripTab.places:
        return const _PlacesPreviewTab();
      default:
        return _ComingSoonTab(label: tab.label);
    }
  }
}

/// One slot in the collapsed bar. An empty slot (no tab assigned) is a drop
/// target but not draggable, since there's nothing in it to drag.
class _BarSlot extends StatelessWidget {
  const _BarSlot({
    required this.tab,
    required this.selected,
    required this.onSelect,
    required this.onDropped,
  });

  final _TripTab? tab;
  final bool selected;
  final ValueChanged<_TripTab> onSelect;
  final ValueChanged<_TripTab> onDropped;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_TripTab>(
      onWillAcceptWithDetails: (details) => details.data != tab,
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        final currentTab = tab;
        if (currentTab == null) {
          return _EmptySlot(highlighted: highlighted);
        }
        final content = _NavButtonContent(
          tab: currentTab,
          selected: selected,
          highlighted: highlighted,
        );
        return GestureDetector(
          onTap: () => onSelect(currentTab),
          child: Draggable<_TripTab>(
            data: currentTab,
            feedback: _DragFeedback(tab: currentTab),
            childWhenDragging: Opacity(opacity: 0.25, child: content),
            child: content,
          ),
        );
      },
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 40,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(
            color: highlighted
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: highlighted ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _NavButtonContent extends StatelessWidget {
  const _NavButtonContent({
    required this.tab,
    required this.selected,
    this.highlighted = false,
  });

  final _TripTab tab;
  final bool selected;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = highlighted
        ? colorScheme.primary
        : selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(tab.icon, color: color),
        const SizedBox(height: 2),
        Text(
          tab.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.tab});

  final _TripTab tab;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: _NavButtonContent(tab: tab, selected: false),
      ),
    );
  }
}

/// The panel that slides up above the bar when the hamburger button is
/// tapped, listing every tab not currently in a bar slot. Each is
/// draggable onto a bar slot, or tappable to jump straight to it (which
/// also collapses the panel). The whole panel is itself a drop target, so
/// dragging a bar tab up here removes it from the bar.
class _OverflowPanel extends StatelessWidget {
  const _OverflowPanel({
    super.key,
    required this.tabs,
    required this.onSelect,
    required this.onDropped,
  });

  final List<_TripTab> tabs;
  final ValueChanged<_TripTab> onSelect;
  final ValueChanged<_TripTab> onDropped;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_TripTab>(
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          decoration: candidateData.isNotEmpty
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Drag to rearrange your bar',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final tab in tabs)
                    Draggable<_TripTab>(
                      data: tab,
                      feedback: _DragFeedback(tab: tab),
                      childWhenDragging: Opacity(
                        opacity: 0.25,
                        child: _HiddenChip(tab: tab, onTap: () {}),
                      ),
                      child: _HiddenChip(tab: tab, onTap: () => onSelect(tab)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HiddenChip extends StatelessWidget {
  const _HiddenChip({required this.tab, required this.onTap});

  final _TripTab tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Chip(avatar: Icon(tab.icon, size: 18), label: Text(tab.label)),
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
