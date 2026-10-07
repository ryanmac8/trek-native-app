import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../addons/addon_flags.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/place_category_colors.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo sections the issue #2 nav structure calls for. Every tab
/// is a placeholder — none of those data models exist yet (issues #4–#9).
///
/// Tabs backed by a Trek add-on are shown only while that add-on is enabled
/// on the server ([addonFlagsProvider]): Budget needs `budget`, Packing and
/// Todos need `packing` ("Lists"). Days and Places are always shown.
class TripDashboardScreen extends ConsumerStatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripDashboardScreen> createState() =>
      _TripDashboardScreenState();
}

class _TripDashboardScreenState extends ConsumerState<TripDashboardScreen> {
  String _selectedLabel = _tabs.first.label;

  static const _tabs = [
    (label: 'Days', icon: Icons.calendar_today, addonId: null),
    (label: 'Places', icon: Icons.place, addonId: null),
    (label: 'Budget', icon: Icons.attach_money, addonId: AddonIds.budget),
    (label: 'Packing', icon: Icons.checklist, addonId: AddonIds.packing),
    (label: 'Todos', icon: Icons.task_alt, addonId: AddonIds.packing),
  ];

  Widget _tabBody(String label) => switch (label) {
    'Places' => const _PlacesPreviewTab(),
    _ => _ComingSoonTab(label: label),
  };

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(addonFlagsProvider);
    final tabs = [
      for (final tab in _tabs)
        if (tab.addonId == null || flags.isEnabled(tab.addonId!)) tab,
    ];
    // If the selected tab's add-on was just switched off, fall back to the
    // first tab rather than pointing past the end of the bar.
    final selected = tabs.indexWhere((tab) => tab.label == _selectedLabel);
    final tabIndex = selected == -1 ? 0 : selected;

    return Scaffold(
      appBar: AppBar(title: Text('Trip ${widget.tripId}')),
      body: IndexedStack(
        index: tabIndex,
        children: [for (final tab in tabs) _tabBody(tab.label)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedLabel = tabs[index].label),
        destinations: [
          for (final tab in tabs)
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
