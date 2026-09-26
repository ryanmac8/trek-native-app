import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../journey/journey_models.dart';
import '../../network/api_exception.dart';
import 'journey_widgets.dart';

/// One journey: its stats, linked trips, contributors, and its entries
/// grouped by date (first slice of issue #20). Read-only. Skeleton
/// suggestions derived from linked trips show as muted "Suggested" rows,
/// unless the viewer has hidden them.
///
/// Offline-first like [JourneyListScreen]: the cached snapshot paints
/// first, a failed refresh keeps it on screen with an offline notice, and
/// with nothing cached an explicit offline state with a retry is shown. A
/// 404 (journey deleted or unshared, or the addon switched off) replaces
/// the cached copy with an explanation instead.
class JourneyDetailScreen extends ConsumerStatefulWidget {
  const JourneyDetailScreen({super.key, required this.journeyId});

  final int journeyId;

  @override
  ConsumerState<JourneyDetailScreen> createState() =>
      _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends ConsumerState<JourneyDetailScreen> {
  CachedJourney<JourneyDetail>? _journey;
  bool _stale = false;
  Object? _error;
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
    final repository = ref.read(journeyRepositoryProvider);

    final cached = await repository.cachedJourney(widget.journeyId);
    if (!mounted) return;
    if (cached != null && _journey == null) {
      setState(() {
        _journey = cached;
        _stale = true;
      });
    }

    try {
      final fresh = await repository.refreshJourney(widget.journeyId);
      if (!mounted) return;
      setState(() {
        _journey = fresh;
        _stale = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _stale = _journey != null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journey = _journey?.value;
    return Scaffold(
      appBar: AppBar(title: Text(journey?.title ?? 'Journey')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final cached = _journey;
    final error = _error;
    final gone = error is ServerException && error.statusCode == 404;

    if (gone || (cached == null && !_loading)) {
      return FillScrollable(
        child: JourneyLoadError(
          error: error,
          what: 'this journey',
          onRetry: _load,
        ),
      );
    }

    if (cached == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 72),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 120),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 160),
        ],
      );
    }

    final journey = cached.value;
    final entries = journey.visibleEntries;
    final byDate = <String, List<JourneyEntry>>{};
    for (final entry in entries) {
      (byDate[entry.entryDate] ??= []).add(entry);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_stale && !_loading) ...[
          JourneyStaleBanner(
            what: 'this journey',
            fetchedAt: cached.fetchedAt,
            onRetry: _load,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _HeaderCard(journey: journey),
        if (journey.trips.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _TripsCard(trips: journey.trips),
        ],
        if (journey.contributors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _ContributorsCard(contributors: journey.contributors),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (entries.isEmpty)
          const EmptyState(icon: Icons.edit_note, message: 'No entries yet.'),
        for (final MapEntry(key: date, value: dayEntries)
            in byDate.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              formatJourneyDate(date),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final entry in dayEntries) ...[
            _EntryCard(entry: entry),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.journey});

  final JourneyDetail journey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final role = journey.myRole;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (journey.subtitle != null) ...[
            Text(journey.subtitle!, style: textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Chip(
                label: Text(journey.status.label),
                visualDensity: VisualDensity.compact,
              ),
              if (role != null)
                Chip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(role.label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _Stat(value: journey.statEntries, label: 'Entries'),
              _Stat(value: journey.statPhotos, label: 'Photos'),
              _Stat(value: journey.statPlaces, label: 'Places'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: textTheme.titleLarge),
          Text(label, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TripsCard extends StatelessWidget {
  const _TripsCard({required this.trips});

  final List<JourneyTrip> trips;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trips', style: textTheme.titleSmall),
          for (final trip in trips)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.card_travel),
              title: Text(trip.title),
              subtitle: Text(
                [
                  ?formatJourneyDateRange(trip.startDate, trip.endDate),
                  '${trip.placeCount} ${trip.placeCount == 1 ? 'place' : 'places'}',
                ].join(' · '),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContributorsCard extends StatelessWidget {
  const _ContributorsCard({required this.contributors});

  final List<JourneyContributor> contributors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contributors', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final c in contributors)
                Chip(
                  avatar: CircleAvatar(
                    child: Text(
                      c.username.isEmpty ? '?' : c.username[0].toUpperCase(),
                    ),
                  ),
                  label: Text('${c.username} · ${c.role.label}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final JourneyEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final muted = colorScheme.onSurfaceVariant;

    if (entry.type == JourneyEntryType.skeleton) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline, color: muted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title ?? entry.locationName ?? 'Untitled stop',
                    style: textTheme.bodyLarge?.copyWith(color: muted),
                  ),
                  Text(
                    entry.sourceTripName == null
                        ? 'Suggested'
                        : 'Suggested from ${entry.sourceTripName}',
                    style: textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // A titleless entry is headed by its location, so it isn't repeated.
    final meta = [
      ?entry.entryTime,
      if (entry.title != null) ?entry.locationName,
      ?entry.mood,
      ?entry.weather,
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (entry.type == JourneyEntryType.checkin) ...[
                Icon(Icons.place, size: 18, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  entry.title ??
                      entry.locationName ??
                      (entry.type == JourneyEntryType.checkin
                          ? 'Check-in'
                          : 'Untitled entry'),
                  style: textTheme.titleMedium,
                ),
              ),
              if (entry.photoCount > 0) ...[
                Icon(Icons.photo_outlined, size: 18, color: muted),
                const SizedBox(width: AppSpacing.xs),
                Text('${entry.photoCount}', style: textTheme.bodySmall),
              ],
            ],
          ),
          if (meta.isNotEmpty)
            Text(
              meta.join(' · '),
              style: textTheme.bodySmall?.copyWith(color: muted),
            ),
          if (entry.story != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(entry.story!, style: textTheme.bodyMedium),
          ],
          if (entry.pros.isNotEmpty || entry.cons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final pro in entry.pros) Text('+ $pro'),
            for (final con in entry.cons) Text('− $con'),
          ],
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in entry.tags)
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
