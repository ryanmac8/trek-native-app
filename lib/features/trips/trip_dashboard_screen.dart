import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../places/place.dart';
import '../places/category_avatar.dart';
import '../places/place_form_screen.dart';

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
/// screen, a failed background refresh just leaves them be.
///
/// Create (the add button), edit, and delete (tap a row) apply to the cache
/// at once and sync in the background; a row with an unsynced change shows
/// a pending icon, and one whose edit hit a conflict shows a warning that
/// opens the keep-mine/use-theirs choice. This still shows every place in
/// the trip, not yet narrowed to the "not yet assigned to a day" pool —
/// that filter depends on a day's assignments exposing place ids, which the
/// Days tab (issue #4) doesn't model yet.
class _PlacesTab extends ConsumerStatefulWidget {
  const _PlacesTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_PlacesTab> createState() => _PlacesTabState();
}

class _PlacesTabState extends ConsumerState<_PlacesTab> {
  List<Place>? _places;
  Object? _error;
  List<PlaceCategoryRef> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
  }

  /// Cached categories first, then a background refresh. Failures keep
  /// whatever is cached — the picker just offers fewer choices.
  Future<void> _loadCategories() async {
    final repository = ref.read(categoriesRepositoryProvider);
    try {
      final cached = await repository.cachedCategories();
      if (mounted && cached.isNotEmpty) setState(() => _categories = cached);
      final refreshed = await repository.refreshCategories();
      if (mounted) setState(() => _categories = refreshed);
    } catch (_) {
      // Offline with nothing cached, or the server refused: keep the cache.
    }
  }

  /// [category] with its name/color/icon filled in from the category list
  /// when it's a bare id — a category picked locally and not yet synced.
  PlaceCategoryRef? _resolveCategory(PlaceCategoryRef? category) {
    if (category == null || category.name != null) return category;
    for (final known in _categories) {
      if (known.id == category.id) return known;
    }
    return category;
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

  Future<void> _reloadFromCache() async {
    final cached = await ref
        .read(placesRepositoryProvider)
        .cachedPlaces(widget.tripId);
    if (!mounted) return;
    setState(() {
      _places = cached;
      _error = null;
    });
  }

  /// Pushes queued changes, then shows whatever the cache holds now. Offline
  /// is silent — the rows' pending icons already say it.
  Future<void> _sync() async {
    final result = await ref
        .read(placesRepositoryProvider)
        .syncPending(widget.tripId);
    result.rejections.forEach(AppMessenger.showError);
    await _reloadFromCache();
  }

  Future<void> _addPlace() async {
    final result = await Navigator.of(context).push<PlaceFormResult>(
      MaterialPageRoute(
        builder: (_) => PlaceFormScreen(categories: _categories),
      ),
    );
    final input = result?.input;
    if (input == null) return;
    await ref.read(placesRepositoryProvider).createPlace(widget.tripId, input);
    await _reloadFromCache();
    await _sync();
  }

  Future<void> _openPlace(Place place) async {
    if (place.syncStatus == PlaceSyncStatus.conflict) {
      return _resolveConflict(place);
    }
    final result = await Navigator.of(context).push<PlaceFormResult>(
      MaterialPageRoute(
        builder: (_) => PlaceFormScreen(place: place, categories: _categories),
      ),
    );
    if (result == null) return;
    final repository = ref.read(placesRepositoryProvider);
    final input = result.input;
    if (result.delete) {
      await repository.deletePlace(widget.tripId, place.id);
    } else if (input != null) {
      await repository.updatePlace(widget.tripId, place, input);
    }
    await _reloadFromCache();
    await _sync();
  }

  Future<void> _resolveConflict(Place place) async {
    final keepMine = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit conflict'),
        content: Text(
          'Someone else changed "${place.name}" while your edit was '
          'waiting to sync. Keep your version, or use theirs?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Use theirs'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keep mine'),
          ),
        ],
      ),
    );
    if (keepMine == null) return;
    await ref
        .read(placesRepositoryProvider)
        .resolveConflict(widget.tripId, place.id, keepMine: keepMine);
    await _reloadFromCache();
    await _sync();
  }

  Future<void> _refresh() async {
    final repository = ref.read(placesRepositoryProvider);
    try {
      final sync = await repository.syncPending(widget.tripId);
      sync.rejections.forEach(AppMessenger.showError);
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
    return Scaffold(
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add place',
        onPressed: _addPlace,
        child: const Icon(Icons.add_location_alt_outlined),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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
            leading: _SyncStatusIcon(status: place.syncStatus),
            title: place.name,
            subtitle: _subtitle(place),
            trailing: _CategoryBadge(
              category: _resolveCategory(place.category),
            ),
            onTap: () => _openPlace(place),
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

/// Leading marker for a place with a change the server hasn't accepted yet
/// (pending) or one waiting on the user to settle a conflict. Nothing for a
/// synced place.
class _SyncStatusIcon extends StatelessWidget {
  const _SyncStatusIcon({required this.status});

  final PlaceSyncStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      PlaceSyncStatus.synced => const SizedBox.shrink(),
      PlaceSyncStatus.pending => const Tooltip(
        message: 'Waiting to sync',
        child: Icon(Icons.cloud_upload_outlined),
      ),
      PlaceSyncStatus.conflict => const Tooltip(
        message: 'Edit conflict — tap to resolve',
        child: Icon(Icons.warning_amber_rounded, color: AppColors.warning),
      ),
    };
  }
}

/// A small colored chip for a place's category, using the real color/icon
/// Trek's backend returns per-category (see [PlaceCategoryRef]) rather than
/// the design system's fixed default-category tokens, since a place's
/// actual category may be one of the server's custom categories.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final PlaceCategoryRef? category;

  @override
  Widget build(BuildContext context) {
    final category = this.category;
    if (category == null) return const SizedBox.shrink();
    return Chip(
      avatar: CategoryAvatar(category: category),
      label: Text(category.name ?? 'Category'),
    );
  }
}
