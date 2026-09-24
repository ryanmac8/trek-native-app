import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../atlas/atlas_models.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';

/// The Atlas stats dashboard (first slice of issue #18): totals, the
/// next-trip countdown and last trip, most-visited country, travel streak,
/// and the continents breakdown, from `GET /api/addons/atlas/stats`.
///
/// Per docs/offline-first.md it reads through [AtlasRepository]: the
/// last-known stats paint from the local cache first, and a failed refresh
/// keeps them on screen with an offline notice rather than blanking or
/// throwing. With nothing cached and no connection, an explicit offline
/// state with a retry is shown. Trip countdowns are computed on the device
/// from the trip dates, so they stay correct while the cache ages.
class AtlasScreen extends ConsumerStatefulWidget {
  const AtlasScreen({super.key, this.clock = DateTime.now});

  /// The current time, injectable for tests.
  final DateTime Function() clock;

  @override
  ConsumerState<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends ConsumerState<AtlasScreen> {
  CachedAtlasStats? _stats;
  Object? _error;
  bool _stale = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = ref.read(atlasRepositoryProvider);

    // Paint the cached stats first so the screen isn't blank while the
    // refresh runs.
    final cached = await repository.cachedStats();
    if (mounted && cached != null && _stats == null) {
      setState(() {
        _stats = cached;
        _stale = true;
      });
    }

    try {
      final fresh = await repository.refreshStats();
      if (!mounted) return;
      setState(() {
        _stats = fresh;
        _stale = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep showing the cached stats (marked stale) if there are any;
        // otherwise surface the failure so the screen can offer a retry.
        if (_stats == null) {
          _error = e;
        } else {
          _stale = true;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atlas')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cached = _stats;

    if (cached == null && _loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 72),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 160),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 120),
        ],
      );
    }

    if (cached == null) {
      final offline = _error is NetworkException;
      return _Scrollable(
        child: EmptyState(
          icon: offline ? Icons.cloud_off : Icons.error_outline,
          message: offline
              ? "You're offline, and your Atlas hasn't been loaded yet."
              : "Couldn't load your Atlas.",
          action: FilledButton(onPressed: _load, child: const Text('Retry')),
        ),
      );
    }

    final stats = cached.stats;
    if (stats.isEmpty) {
      return const _Scrollable(
        child: EmptyState(
          icon: Icons.public,
          message:
              'No travels yet. Trips and places you add will show up here.',
        ),
      );
    }

    final today = widget.clock();
    final nextDays = stats.nextTrip?.daysUntil(today);
    final showNext =
        stats.nextTrip != null && nextDays != null && nextDays >= 0;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_stale && !_loading) ...[
          _StaleBanner(fetchedAt: cached.fetchedAt, onRetry: _load),
          const SizedBox(height: AppSpacing.md),
        ],
        if (showNext) ...[
          _NextTripCard(trip: stats.nextTrip!, daysUntil: nextDays),
          const SizedBox(height: AppSpacing.md),
        ],
        if (stats.lastTrip != null) ...[
          _LastTripCard(trip: stats.lastTrip!, today: today),
          const SizedBox(height: AppSpacing.md),
        ],
        _TotalsGrid(stats: stats),
        const SizedBox(height: AppSpacing.md),
        _HighlightsCard(stats: stats),
        if (stats.continents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _ContinentsCard(continents: stats.continents),
        ],
      ],
    );
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
          Expanded(child: Text('Offline — showing stats from $date.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _NextTripCard extends StatelessWidget {
  const _NextTripCard({required this.trip, required this.daysUntil});

  final AtlasNextTrip trip;
  final int daysUntil;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final countdown = switch (daysUntil) {
      0 => 'Starts today',
      1 => 'Starts tomorrow',
      _ => 'In $daysUntil days',
    };
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.flight_takeoff),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next trip', style: textTheme.labelMedium),
                Text(trip.title, style: textTheme.titleMedium),
              ],
            ),
          ),
          Text(countdown, style: textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _LastTripCard extends StatelessWidget {
  const _LastTripCard({required this.trip, required this.today});

  final AtlasLastTrip trip;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final days = trip.daysSinceEnd(today);
    final ago = switch (days) {
      null => null,
      <= 0 => 'Ended today',
      1 => 'Ended yesterday',
      _ => 'Ended $days days ago',
    };
    final code = trip.countryCode;
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.flight_land),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last trip', style: textTheme.labelMedium),
                Text(
                  code == null
                      ? trip.title
                      : '${countryFlag(code)} ${trip.title}',
                  style: textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (ago != null) Text(ago, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.stats});

  final AtlasStats stats;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Countries', stats.totalCountries),
      ('Trips', stats.totalTrips),
      ('Places', stats.totalPlaces),
      ('Cities', stats.totalCities),
      ('Days', stats.totalDays),
      ('Planned', stats.totalCountriesPlanned),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.3,
      children: [
        for (final (label, value) in tiles)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.stats});

  final AtlasStats stats;

  @override
  Widget build(BuildContext context) {
    final mostVisited = stats.mostVisited;
    final rows = <(IconData, String, String)>[
      if (mostVisited != null)
        (
          Icons.star_outline,
          'Most visited',
          '${mostVisited.flag} ${mostVisited.code} · '
              '${_plural(mostVisited.placeCount, 'place')}',
        ),
      (
        Icons.local_fire_department_outlined,
        'Travel streak',
        _plural(stats.streak, 'year'),
      ),
      (Icons.event, 'Trips this year', '${stats.tripsThisYear}'),
      if (stats.firstYear != null)
        (Icons.history, 'Traveling since', '${stats.firstYear}'),
    ];
    return AppCard(
      child: Column(
        children: [
          for (final (icon, label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(label)),
                  Text(value),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinentsCard extends StatelessWidget {
  const _ContinentsCard({required this.continents});

  final Map<String, int> continents;

  @override
  Widget build(BuildContext context) {
    final sorted = continents.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = sorted.first.value;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Continents', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(width: 110, child: Text(entry.key)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : entry.value / max,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${entry.value}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _plural(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';
