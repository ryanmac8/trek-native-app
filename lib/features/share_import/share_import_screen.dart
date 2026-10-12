import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/loading_indicator.dart';
import '../../network/api_exception.dart';
import '../../share_intake/shared_map_link.dart';
import 'share_import_api.dart';
import 'share_import_repository.dart';

/// Shown when a map link is shared into Trek from another app: pick a trip
/// and add the place to its place pool.
///
/// The trip list comes from the local cache first and is refreshed in the
/// background; offline, the cached list is used and the import is queued.
/// Closing the screen (or finishing an import) clears
/// [incomingShareProvider], and the router moves on to `/trips`.
class ShareImportScreen extends ConsumerStatefulWidget {
  const ShareImportScreen({super.key});

  @override
  ConsumerState<ShareImportScreen> createState() => _ShareImportScreenState();
}

class _ShareImportScreenState extends ConsumerState<ShareImportScreen> {
  late final SharedMapLink? _link = ref.read(incomingShareProvider).value;
  late final _nameController = TextEditingController(
    text: _link?.suggestedName ?? '',
  );

  List<ShareTargetTrip>? _trips;
  bool _refreshing = true;
  bool _offline = false;
  String? _loadError;
  int? _selectedTripId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    final repository = ref.read(shareImportRepositoryProvider);
    try {
      final cached = await repository.cachedTrips();
      if (mounted && cached != null) setState(() => _trips = cached);
    } catch (error) {
      debugPrint('ShareImportScreen: reading cached trips failed: $error');
    }
    await _refreshTrips();
  }

  Future<void> _refreshTrips() async {
    setState(() {
      _refreshing = true;
      _loadError = null;
    });
    try {
      final trips = await ref
          .read(shareImportRepositoryProvider)
          .refreshTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _offline = false;
      });
    } on NetworkException {
      if (mounted) setState(() => _offline = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _close() => ref.read(incomingShareProvider).value = null;

  Future<void> _submit() async {
    final link = _link;
    final trip = _trips?.firstWhere((trip) => trip.id == _selectedTripId);
    if (link == null || trip == null) return;

    setState(() => _submitting = true);
    final ShareImportOutcome outcome;
    try {
      outcome = await ref
          .read(shareImportRepositoryProvider)
          .importLink(trip: trip, link: link, name: _nameController.text);
    } catch (error) {
      debugPrint('ShareImportScreen: import failed: $error');
      if (mounted) setState(() => _submitting = false);
      AppMessenger.showError('Couldn\'t save the shared place.');
      return;
    }
    if (!mounted) return;

    switch (outcome) {
      case PlaceAdded(:final name):
        AppMessenger.showSuccess('Added "$name" to ${trip.title}.');
        _close();
      case ImportQueued():
        AppMessenger.showInfo(
          'You\'re offline. The place will be added to ${trip.title} '
          'when you\'re back online.',
        );
        _close();
      case ImportFailed(:final message):
        setState(() => _submitting = false);
        AppMessenger.showError(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add to a trip'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _close,
        ),
      ),
      body: link == null
          ? const EmptyState(
              icon: Icons.link_off,
              message: 'Nothing was shared.',
            )
          : _buildBody(context, link),
      bottomNavigationBar: link == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FilledButton(
                  onPressed: _selectedTripId == null || _submitting
                      ? null
                      : _submit,
                  child: Text(_submitting ? 'Adding…' : 'Add to place pool'),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context, SharedMapLink link) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _LinkCard(link: link),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Place name',
            helperText: 'Leave empty to use the name from the map link.',
          ),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Trip', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (_offline && _trips != null)
          const _Notice(
            icon: Icons.cloud_off,
            message:
                'You\'re offline — showing trips saved on this device. '
                'The place will be added once you\'re back online.',
          ),
        ..._buildTripList(),
      ],
    );
  }

  List<Widget> _buildTripList() {
    final trips = _trips;
    if (trips == null) {
      if (_refreshing) return const [LoadingIndicator()];
      return [
        _Notice(
          icon: _offline ? Icons.cloud_off : Icons.error_outline,
          message: _offline
              ? 'You\'re offline, and your trips haven\'t been loaded on '
                    'this device yet.'
              : _loadError ?? 'Couldn\'t load your trips.',
        ),
        TextButton(onPressed: _refreshTrips, child: const Text('Try again')),
      ];
    }
    if (trips.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.card_travel,
          message: 'Create a trip first, then share the link again.',
        ),
      ];
    }
    return [
      for (final trip in trips)
        ListTile(
          key: ValueKey('share-trip-${trip.id}'),
          title: Text(trip.title),
          subtitle: _dateRange(trip) == null ? null : Text(_dateRange(trip)!),
          selected: trip.id == _selectedTripId,
          trailing: trip.id == _selectedTripId
              ? const Icon(Icons.check_circle)
              : const Icon(Icons.radio_button_unchecked),
          onTap: _submitting
              ? null
              : () => setState(() => _selectedTripId = trip.id),
        ),
    ];
  }

  static String? _dateRange(ShareTargetTrip trip) {
    final start = trip.startDate;
    final end = trip.endDate;
    if (start == null && end == null) return null;
    if (start == null || end == null || start == end) return start ?? end;
    return '$start – $end';
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final SharedMapLink link;

  static const _providerNames = {
    MapLinkProvider.google: 'Google Maps',
    MapLinkProvider.apple: 'Apple Maps',
    MapLinkProvider.amap: 'Amap',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.place, color: colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_providerNames[link.provider]} link',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  link.url,
                  style: textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (link.hasCoordinates) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${link.lat!.toStringAsFixed(5)}, '
                    '${link.lng!.toStringAsFixed(5)}',
                    style: textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
