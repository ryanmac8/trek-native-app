import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../transit/transit_format.dart';
import '../../transit/transit_models.dart';
import '../../transit/transit_repository.dart';

/// Transit + airport search (first slice of issue #12).
///
/// Per docs/offline-first.md the screen reads through [TransitRepository]:
/// the last results for a query paint from the local cache, and a failed
/// refresh falls back to that cache with an offline notice rather than
/// blanking or throwing. Search and route planning still need the network
/// (there is no bundled transit graph); when nothing is cached, an explicit
/// offline state with a retry is shown.
///
/// This slice is search + route results only. Transport entries on the
/// itinerary and creating a journey from a result both need the Days
/// feature (issue #4) and are deferred with it; so are a departure-time
/// picker and transit-mode filters.
class TransitSearchScreen extends ConsumerStatefulWidget {
  const TransitSearchScreen({super.key});

  @override
  ConsumerState<TransitSearchScreen> createState() =>
      _TransitSearchScreenState();
}

enum _Mode { routes, airports }

class _TransitSearchScreenState extends ConsumerState<TransitSearchScreen> {
  _Mode _mode = _Mode.routes;

  TransitPlace? _origin;
  TransitPlace? _destination;
  List<TransitItinerary>? _itineraries;
  Object? _routeError;
  bool _routeFromCache = false;
  bool _planning = false;

  TransitRepository get _repository => ref.read(transitRepositoryProvider);

  Future<void> _planRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    setState(() {
      _planning = true;
      _routeError = null;
    });

    final query = TransitPlanQuery(
      from: origin.coordinate,
      to: destination.coordinate,
    );
    // Paint any cached plan for this exact query first.
    final cached = await _repository.cachedRoute(query);
    if (mounted && cached != null) {
      setState(() {
        _itineraries = cached;
        _routeFromCache = true;
      });
    }

    try {
      final itineraries = await _repository.planRoute(query);
      if (!mounted) return;
      setState(() {
        _itineraries = itineraries;
        _routeError = null;
        _routeFromCache = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_itineraries == null) {
          _routeError = e;
        } else {
          _routeFromCache = true;
        }
      });
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  void _swapEndpoints() {
    setState(() {
      final origin = _origin;
      _origin = _destination;
      _destination = origin;
      _itineraries = null;
      _routeError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transit')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(
                  value: _Mode.routes,
                  label: Text('Routes'),
                  icon: Icon(Icons.directions_transit),
                ),
                ButtonSegment(
                  value: _Mode.airports,
                  label: Text('Airports'),
                  icon: Icon(Icons.flight),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
          ),
          Expanded(
            child: _mode == _Mode.routes
                ? _buildRoutes(context)
                : const _AirportSearchView(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutes(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        _StopPickerField(
          label: 'From',
          icon: Icons.trip_origin,
          selected: _origin,
          onSelected: (place) => setState(() {
            _origin = place;
            _itineraries = null;
            _routeError = null;
          }),
        ),
        Row(
          children: [
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              onPressed: (_origin == null && _destination == null)
                  ? null
                  : _swapEndpoints,
              icon: const Icon(Icons.swap_vert),
              tooltip: 'Swap',
            ),
          ],
        ),
        _StopPickerField(
          label: 'To',
          icon: Icons.place,
          selected: _destination,
          onSelected: (place) => setState(() {
            _destination = place;
            _itineraries = null;
            _routeError = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: (_origin != null && _destination != null && !_planning)
              ? _planRoute
              : null,
          icon: const Icon(Icons.search),
          label: const Text('Find routes'),
        ),
        const SizedBox(height: AppSpacing.md),
        ..._buildRouteResults(context),
      ],
    );
  }

  List<Widget> _buildRouteResults(BuildContext context) {
    if (_planning && _itineraries == null) {
      return const [SkeletonListTile(), SkeletonListTile()];
    }

    final error = _routeError;
    if (error != null && _itineraries == null) {
      return [_ErrorState(error: error, onRetry: _planRoute)];
    }

    final itineraries = _itineraries;
    if (itineraries == null) return const [];
    if (itineraries.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.directions_off,
          message: 'No transit routes found between these points.',
        ),
      ];
    }

    return [
      if (_routeFromCache)
        const _OfflineNotice(
          message: 'Showing the last results found — you may be offline.',
        ),
      for (final itinerary in itineraries)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _ItineraryCard(itinerary: itinerary),
        ),
    ];
  }
}

/// A "From" / "To" field: type to search stops, tap a result to select it.
/// A selected stop shows as a chip with a clear button.
class _StopPickerField extends ConsumerStatefulWidget {
  const _StopPickerField({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final TransitPlace? selected;
  final ValueChanged<TransitPlace?> onSelected;

  @override
  ConsumerState<_StopPickerField> createState() => _StopPickerFieldState();
}

class _StopPickerFieldState extends ConsumerState<_StopPickerField> {
  final _controller = TextEditingController();
  List<TransitPlace>? _results;
  Object? _error;
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final repository = ref.read(transitRepositoryProvider);
    if (query.trim().length < TransitRepository.minQueryLength) {
      setState(() {
        _results = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    final cached = await repository.cachedStops(query);
    if (mounted && cached != null) setState(() => _results = cached);

    try {
      final results = await repository.searchStops(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_results == null) _error = e;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    if (selected != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: InputChip(
          avatar: Icon(widget.icon, size: 18),
          label: Text(
            selected.area == null
                ? selected.name
                : '${selected.name} · ${selected.area}',
          ),
          onDeleted: () {
            _controller.clear();
            setState(() {
              _results = null;
              _error = null;
            });
            widget.onSelected(null);
          },
        ),
      );
    }

    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onSubmitted: _search,
        ),
        if (_error != null && results == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _error is NetworkException
                  ? "You're offline — can't search stops right now."
                  : "Couldn't search stops.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (results != null && results.isEmpty && !_searching)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: Text('No matching stops.'),
          ),
        if (results != null && results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final place in results)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        place.type == 'STOP'
                            ? Icons.directions_bus
                            : Icons.place_outlined,
                      ),
                      title: Text(place.name),
                      subtitle: place.area == null ? null : Text(place.area!),
                      onTap: () {
                        setState(() => _results = null);
                        widget.onSelected(place);
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({required this.itinerary});

  final TransitItinerary itinerary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatClock(itinerary.startTime)} – '
                '${formatClock(itinerary.endTime)}',
                style: textTheme.titleMedium,
              ),
              Text(
                formatDuration(itinerary.duration),
                style: textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(itinerarySummary(itinerary), style: textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${transferLabel(itinerary.transfers)}'
            '${itinerary.walkSeconds > 0 ? ' · ${formatDuration(itinerary.walkSeconds)} walking' : ''}',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AirportSearchView extends ConsumerStatefulWidget {
  const _AirportSearchView();

  @override
  ConsumerState<_AirportSearchView> createState() => _AirportSearchViewState();
}

class _AirportSearchViewState extends ConsumerState<_AirportSearchView> {
  final _controller = TextEditingController();
  List<Airport>? _airports;
  Object? _error;
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final repository = ref.read(transitRepositoryProvider);
    if (query.trim().isEmpty) {
      setState(() {
        _airports = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    final cached = await repository.cachedAirports(query);
    if (mounted && cached != null) setState(() => _airports = cached);

    try {
      final results = await repository.searchAirports(query);
      if (!mounted) return;
      setState(() {
        _airports = results;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_airports == null) _error = e;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Airport name, city, or code',
            prefixIcon: const Icon(Icons.flight),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onSubmitted: _search,
        ),
        const SizedBox(height: AppSpacing.md),
        ..._results(context),
      ],
    );
  }

  List<Widget> _results(BuildContext context) {
    if (_searching && _airports == null) {
      return const [SkeletonListTile(), SkeletonListTile()];
    }

    final error = _error;
    if (error != null && _airports == null) {
      return [
        _ErrorState(error: error, onRetry: () => _search(_controller.text)),
      ];
    }

    final airports = _airports;
    if (airports == null) return const [];
    if (airports.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.search_off,
          message: 'No airports match that search.',
        ),
      ];
    }

    return [
      for (final airport in airports)
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(airport.iata)),
            title: Text(airport.name),
            subtitle: Text('${airport.city}, ${airport.country}'),
          ),
        ),
    ];
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is NetworkException;
    return EmptyState(
      icon: offline ? Icons.cloud_off : Icons.error_outline,
      message: offline
          ? "You're offline. Transit search needs a connection."
          : "Something went wrong. Please try again.",
      action: FilledButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}
