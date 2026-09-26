import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../journey/journey_models.dart';
import 'journey_widgets.dart';

/// The journeys the user owns or contributes to (first slice of issue
/// #20). Read-only; tapping a journey opens [JourneyDetailScreen].
///
/// Per docs/offline-first.md it reads through [JourneyRepository]: the
/// last-known list paints from the local cache first, and a failed refresh
/// keeps it on screen with an offline notice rather than blanking or
/// throwing. With nothing cached and no connection, an explicit offline
/// state with a retry is shown.
class JourneyListScreen extends ConsumerStatefulWidget {
  const JourneyListScreen({super.key});

  @override
  ConsumerState<JourneyListScreen> createState() => _JourneyListScreenState();
}

class _JourneyListScreenState extends ConsumerState<JourneyListScreen> {
  CachedJourney<JourneyList>? _list;
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

    final cached = await repository.cachedList();
    if (!mounted) return;
    if (cached != null && _list == null) {
      setState(() {
        _list = cached;
        _stale = true;
      });
    }

    try {
      final fresh = await repository.refreshList();
      if (!mounted) return;
      setState(() {
        _list = fresh;
        _stale = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _stale = _list != null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journeys')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final list = _list;

    // The addon gate wins over a cached copy: the server has switched the
    // feature off, so showing old journeys as if merely offline would lie.
    if (isJourneyAddonDisabled(_error) || (list == null && !_loading)) {
      return FillScrollable(
        child: JourneyLoadError(
          error: _error,
          what: 'your journeys',
          onRetry: _load,
        ),
      );
    }

    if (list == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 96),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 96),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_stale && !_loading) ...[
          JourneyStaleBanner(
            what: 'your journeys',
            fetchedAt: list.fetchedAt,
            onRetry: _load,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (list.value.journeys.isEmpty)
          const EmptyState(
            icon: Icons.auto_stories,
            message: 'No journeys yet.',
          ),
        for (final journey in list.value.journeys) ...[
          _JourneyCard(
            journey: journey,
            onTap: () => context.push('/journeys/${journey.id}'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.journey, required this.onTap});

  final JourneySummary journey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final dates = formatJourneyDateRange(
      journey.tripDateMin,
      journey.tripDateMax,
    );
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(journey.title, style: textTheme.titleMedium),
              ),
              if (journey.status != JourneyStatus.active)
                Chip(
                  label: Text(journey.status.label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (journey.subtitle != null)
            Text(
              journey.subtitle!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (dates != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(dates, style: textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              _count(journey.entryCount, 'entry', 'entries'),
              _count(journey.photoCount, 'photo', 'photos'),
              _count(journey.placeCount, 'place', 'places'),
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
