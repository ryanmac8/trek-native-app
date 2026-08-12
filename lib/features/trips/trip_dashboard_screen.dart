import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../places/place.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo sections the issue #2 nav structure calls for. Places
/// (issue #5) reads real data; the rest are still placeholders — none of
/// those data models exist yet (issues #4, #6–#9).
class TripDashboardScreen extends ConsumerStatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripDashboardScreen> createState() =>
      _TripDashboardScreenState();
}

class _TripDashboardScreenState extends ConsumerState<TripDashboardScreen> {
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
          const _ComingSoonTab(label: 'Days'),
          _PlacesTab(tripId: widget.tripId),
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

/// The Places tab: per docs/offline-first.md, the local cache
/// ([PlacesRepository.cachedPlaces]) is the source of truth for what's
/// shown — this paints from it immediately, then refreshes from the network
/// in the background. A [NetworkException] only surfaces as an explicit
/// offline state when there's nothing cached yet; if places are already on
/// screen, a failed background refresh just leaves them be. This first
/// slice of issue #5 shows every place in the trip, not yet narrowed to the
/// "not yet assigned to a day" pool — that filter depends on a day's
/// assignments exposing place ids, which the Days tab (issue #4) doesn't
/// model yet.
class _PlacesTab extends ConsumerStatefulWidget {
  const _PlacesTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_PlacesTab> createState() => _PlacesTabState();
}

class _PlacesTabState extends ConsumerState<_PlacesTab> {
  List<Place>? _places;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(placesRepositoryProvider);
    final cached = await repository.cachedPlaces(widget.tripId);
    if (!mounted) return;
    setState(() {
      _places = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(placesRepositoryProvider);
    try {
      final refreshed = await repository.refreshPlaces(widget.tripId);
      if (!mounted) return;
      setState(() {
        _places = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_places == null || _places!.isEmpty) _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;

    if (places == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (places.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message:
              "You're offline. Places will load once you're "
              'back online.',
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load places.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(icon: Icons.place, message: 'No places yet.');
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: places.length,
        itemBuilder: (context, index) {
          final place = places[index];
          return AppListRow(
            title: place.name,
            subtitle: _subtitle(place),
            trailing: _CategoryBadge(category: place.category),
          );
        },
      ),
    );
  }

  String? _subtitle(Place place) {
    final priceLabel = _priceLabel(place);
    final notes = place.notes;
    if (priceLabel != null && notes != null && notes.isNotEmpty) {
      return '$priceLabel · $notes';
    }
    return priceLabel ?? (notes != null && notes.isNotEmpty ? notes : null);
  }

  String? _priceLabel(Place place) {
    final price = place.price;
    if (price == null) return null;
    final formatted = price == price.roundToDouble()
        ? price.toStringAsFixed(0)
        : price.toStringAsFixed(2);
    final currency = place.currency;
    return currency != null ? '$currency $formatted' : formatted;
  }
}

/// A small colored chip for a place's category, using the real color/icon
/// Trek's backend returns per-category (see [PlaceCategoryRef]) rather than
/// the design system's fixed default-category tokens, since a place's
/// actual category may be one of the user's own custom categories.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final PlaceCategoryRef? category;

  @override
  Widget build(BuildContext context) {
    final category = this.category;
    if (category == null) return const SizedBox.shrink();
    final color =
        _parseColor(category.color) ?? Theme.of(context).colorScheme.primary;
    return Chip(
      avatar: category.icon != null
          ? CircleAvatar(
              backgroundColor: color,
              child: Text(category.icon!, style: const TextStyle(fontSize: 12)),
            )
          : CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(category.name ?? 'Category'),
    );
  }

  /// Parses a `#rrggbb` hex string (Trek's category color format — see
  /// `server/src/db/seeds.ts`) into a [Color]; `null` if it doesn't match.
  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    final normalized = hex.replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final value = int.tryParse(normalized, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}
