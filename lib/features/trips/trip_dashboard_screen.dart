import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accommodations/accommodation.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/place_category_colors.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo/stays sections the issue #2 nav structure calls for. Stays
/// (the first slice of issue #10) reads real data; the rest are still
/// placeholders — none of those data models exist yet (issues #4–#9).
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
    (label: 'Stays', icon: Icons.hotel),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip ${widget.tripId}')),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const _ComingSoonTab(label: 'Days'),
          const _PlacesPreviewTab(),
          const _ComingSoonTab(label: 'Budget'),
          const _ComingSoonTab(label: 'Packing'),
          const _ComingSoonTab(label: 'Todos'),
          _StaysTab(tripId: widget.tripId),
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

/// The Stays tab: per docs/offline-first.md, the local cache
/// ([AccommodationsRepository.cachedAccommodations]) is the source of truth
/// for what's shown — this paints from it immediately, then refreshes from
/// the network in the background. A [NetworkException] only surfaces as an
/// explicit offline state when there's nothing cached yet; if stays are
/// already on screen, a failed background refresh just leaves them be.
///
/// This first slice of issue #10 is read-only: no create/edit/delete, no
/// check-in/check-out day-range picker, and no itinerary-day context —
/// those depend on the place pool (issue #5) and day model (issue #4),
/// neither of which is modeled client-side yet.
class _StaysTab extends ConsumerStatefulWidget {
  const _StaysTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_StaysTab> createState() => _StaysTabState();
}

class _StaysTabState extends ConsumerState<_StaysTab> {
  List<Accommodation>? _accommodations;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(accommodationsRepositoryProvider);
    final cached = await repository.cachedAccommodations(widget.tripId);
    if (!mounted) return;
    setState(() {
      _accommodations = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(accommodationsRepositoryProvider);
    try {
      final refreshed = await repository.refreshAccommodations(widget.tripId);
      if (!mounted) return;
      setState(() {
        _accommodations = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_accommodations == null || _accommodations!.isEmpty) _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accommodations = _accommodations;

    if (accommodations == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (accommodations.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message: "You're offline. Stays will load once you're back online.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load stays.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.hotel,
        message: 'No accommodations yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: accommodations.length,
        itemBuilder: (context, index) {
          final accommodation = accommodations[index];
          return AppListRow(
            title: accommodation.placeName ?? 'Accommodation',
            subtitle: _subtitle(accommodation),
            trailing: accommodation.confirmation != null
                ? const Icon(Icons.confirmation_number_outlined, size: 18)
                : null,
          );
        },
      ),
    );
  }

  /// A "check-in → check-out" line when the user entered dates, otherwise
  /// the place address, otherwise the linked reservation title.
  String? _subtitle(Accommodation accommodation) {
    final checkIn = accommodation.checkIn;
    final checkOut = accommodation.checkOut;
    if (checkIn != null && checkOut != null) return '$checkIn → $checkOut';
    if (checkIn != null) return 'Check in $checkIn';
    if (checkOut != null) return 'Check out $checkOut';

    final address = accommodation.placeAddress;
    if (address != null && address.isNotEmpty) return address;
    return accommodation.reservationTitle;
  }
}
