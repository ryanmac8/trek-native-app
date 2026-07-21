import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../trips/trip.dart';

/// Landing screen once a session is active. Per docs/offline-first.md, the
/// local cache ([TripsRepository.cachedTrips]) is the source of truth for
/// what's shown — this screen paints from it immediately, then refreshes
/// from the network in the background. A [NetworkException] only surfaces
/// as an explicit offline state when there's nothing cached yet; if trips
/// are already on screen, a failed background refresh just leaves them be.
class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  List<Trip>? _trips;
  Object? _error;

  /// 0 = Upcoming Trips, 1 = Past Trips — always defaults to Upcoming.
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(tripsRepositoryProvider);
    final cached = await repository.cachedTrips();
    if (!mounted) return;
    setState(() {
      _trips = cached;
      _error = null;
    });
    await _refresh();
  }

  /// Re-reads the cache without hitting the network — used right after
  /// [CreateTripScreen] returns, so a just-created (possibly still
  /// [Trip.isPending]) trip appears instantly.
  Future<void> _reloadFromCache() async {
    final cached = await ref.read(tripsRepositoryProvider).cachedTrips();
    if (!mounted) return;
    setState(() => _trips = cached);
  }

  Future<void> _refresh() async {
    final repository = ref.read(tripsRepositoryProvider);
    try {
      final refreshed = await repository.refreshTrips();
      if (!mounted) return;
      setState(() {
        _trips = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_trips == null || _trips!.isEmpty) _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New trip',
        onPressed: () async {
          await context.push<void>('/trips/new');
          await _reloadFromCache();
        },
        child: const Icon(Icons.add),
      ),
      body: _buildBody(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flight_takeoff),
            label: 'Upcoming Trips',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Past Trips'),
        ],
      ),
    );
  }

  /// A trip with no end date is still being planned, so it counts as
  /// upcoming rather than past.
  bool _isPast(Trip trip) {
    final end = trip.endDate;
    if (end == null) return false;
    final now = DateTime.now();
    return end.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Upcoming Trips: soonest start date first. Past Trips: most recently
  /// ended first, oldest last. An upcoming trip with no start date yet
  /// (undated, or still `isPending`) sorts after every dated trip — there's
  /// no date to compare it against, so it can't be claimed as "sooner".
  void _sortTrips(List<Trip> trips) {
    trips.sort((a, b) {
      if (_tabIndex == 1) {
        return b.endDate!.compareTo(a.endDate!);
      }
      final aStart = a.startDate;
      final bStart = b.startDate;
      if (aStart == null && bStart == null) return 0;
      if (aStart == null) return 1;
      if (bStart == null) return -1;
      return aStart.compareTo(bStart);
    });
  }

  Widget _buildBody(BuildContext context) {
    final trips = _trips;

    if (trips == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (trips.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message:
              "You're offline. Trips will load once you're "
              'back online.',
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null && error is! UnauthorizedException) {
        // AuthService.needsReconnect (for a 401) is already flagged by
        // ApiClient's onUnauthorized callback and surfaced by
        // SyncStatusShell — nothing trip-specific to say for that case, so
        // it falls through to the plain empty state below like a genuine
        // "no trips yet".
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load trips.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.card_travel,
        message: 'No trips yet.',
      );
    }

    final filtered = trips
        .where((trip) => _isPast(trip) == (_tabIndex == 1))
        .toList();
    _sortTrips(filtered);

    if (filtered.isEmpty) {
      return EmptyState(
        icon: _tabIndex == 0 ? Icons.card_travel : Icons.history,
        message: _tabIndex == 0 ? 'No upcoming trips.' : 'No past trips.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final trip = filtered[index];
          return AppListRow(
            title: trip.title,
            subtitle: trip.isPending ? 'Syncing…' : _dateRangeLabel(trip),
            // A static icon, not a spinner — this reflects "queued to sync
            // once online", not active in-progress work.
            trailing: trip.isPending
                ? Icon(
                    Icons.sync,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )
                : const Icon(Icons.chevron_right),
            // A pending trip has no server id yet, so there's nowhere to
            // navigate to until it syncs. Uses push (not go) so the trip
            // detail screen lands on the navigation stack — go replaces
            // the current location instead, which left no way back to the
            // trip list (no AppBar back button, no swipe-back gesture).
            onTap: trip.isPending
                ? null
                : () => context.push('/trips/${trip.id}'),
          );
        },
      ),
    );
  }

  String? _dateRangeLabel(Trip trip) {
    final start = trip.startDate;
    final end = trip.endDate;
    if (start == null || end == null) return null;
    String fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
    return '${fmt(start)} – ${fmt(end)} · ${trip.dayCount} days';
  }
}
