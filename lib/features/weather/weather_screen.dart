import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/loading_indicator.dart';
import '../../network/api_exception.dart';
import '../../weather/weather_destinations.dart';
import '../../weather/weather_format.dart';
import '../../weather/weather_models.dart';
import '../../weather/weather_repository.dart';

/// The `/weather` screen, reachable from the trip list's app-bar weather icon.
///
/// Pick a destination, then see current conditions and a seven-day forecast
/// for it. Reads go through [WeatherRepository]: cached answers paint first and
/// a failed refresh falls back to them behind an offline notice.
///
/// The destination list is a bundled stand-in (see `weather_destinations.dart`)
/// — Trek shows weather per trip place, and this app has neither trips nor
/// geocoding yet. See docs/weather.md.
class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  static const _forecastDays = 7;

  TravelDestination? _selected;
  Future<_WeatherView>? _future;

  void _select(TravelDestination destination) {
    setState(() {
      _selected = destination;
      _future = _load(destination);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _future = null;
    });
  }

  Future<_WeatherView> _load(
    TravelDestination destination, {
    bool forceRefresh = false,
  }) async {
    final repository = ref.read(weatherRepositoryProvider);

    // Current conditions are the one call that can throw when offline with no
    // cache — treat that as "no current data" rather than failing the screen,
    // so a partial forecast still shows. Non-network errors still propagate.
    WeatherSnapshot? current;
    try {
      current = await repository.report(
        destination.point,
        forceRefresh: forceRefresh,
      );
    } on NetworkException {
      current = null;
    }

    // forecast() degrades per-day and never throws for the network.
    final forecast = await repository.forecast(
      destination.point,
      start: DateTime.now(),
      days: _forecastDays,
      forceRefresh: forceRefresh,
    );
    return _WeatherView(current: current, forecast: forecast);
  }

  Future<void> _refresh() async {
    final destination = _selected;
    if (destination == null) return;
    setState(() => _future = _load(destination, forceRefresh: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final destination = _selected;
    return Scaffold(
      appBar: AppBar(
        title: Text(destination?.label ?? 'Weather'),
        leading: destination == null
            ? null
            : BackButton(onPressed: _clearSelection),
      ),
      body: destination == null
          ? _DestinationPicker(onSelected: _select)
          : _WeatherBody(
              destination: destination,
              future: _future!,
              onRetry: () => _select(destination),
              onRefresh: _refresh,
            ),
    );
  }
}

class _WeatherView {
  const _WeatherView({required this.current, required this.forecast});

  /// Null when offline with nothing cached for current conditions.
  final WeatherSnapshot? current;
  final TripForecast forecast;

  bool get hasNoData =>
      current == null && forecast.days.every((d) => d.weather == null);

  bool get servedOffline =>
      current == null || current!.stale || forecast.isPartial;
}

class _DestinationPicker extends StatefulWidget {
  const _DestinationPicker({required this.onSelected});

  final void Function(TravelDestination) onSelected;

  @override
  State<_DestinationPicker> createState() => _DestinationPickerState();
}

class _DestinationPickerState extends State<_DestinationPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? popularDestinations
        : popularDestinations
              .where((d) => d.label.toLowerCase().contains(query))
              .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search a destination',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? const EmptyState(
                  icon: Icons.travel_explore,
                  message: 'No destination matches that search.',
                )
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final destination = matches[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(destination.name),
                      subtitle: Text(destination.country),
                      onTap: () => widget.onSelected(destination),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _WeatherBody extends StatelessWidget {
  const _WeatherBody({
    required this.destination,
    required this.future,
    required this.onRetry,
    required this.onRefresh,
  });

  final TravelDestination destination;
  final Future<_WeatherView> future;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WeatherView>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }

        final offlineWithNothing =
            snapshot.hasError || (snapshot.data?.hasNoData ?? false);
        if (offlineWithNothing) {
          final isNetwork =
              snapshot.error is NetworkException || !snapshot.hasError;
          return EmptyState(
            icon: Icons.cloud_off,
            message: isNetwork
                ? 'You appear to be offline, and there is no saved forecast '
                      'for ${destination.name} yet.'
                : 'Could not load the weather for ${destination.name}.',
            action: FilledButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          );
        }

        final view = snapshot.data!;
        final current = view.current;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (view.servedOffline) const _OfflineBanner(),
              if (current != null)
                _CurrentConditionsCard(
                  destination: destination,
                  snapshot: current,
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '7-day forecast',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final day in view.forecast.days) _ForecastRow(day: day),
            ],
          ),
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing saved weather — pull to refresh when you are back '
              'online.',
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

class _CurrentConditionsCard extends StatelessWidget {
  const _CurrentConditionsCard({
    required this.destination,
    required this.snapshot,
  });

  final TravelDestination destination;
  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    final theme = Theme.of(context);
    final qualifier = weatherQualifier(report);

    return AppCard(
      child: Row(
        children: [
          Icon(
            weatherIcon(report.conditionBucket),
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.isMissing ? '—' : formatTemp(report.temp),
                  style: theme.textTheme.headlineMedium,
                ),
                if (report.description.isNotEmpty)
                  Text(report.description, style: theme.textTheme.bodyMedium),
                if (qualifier != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      qualifier,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day});

  final ForecastDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = formatForecastDay(day.date);
    final weather = day.weather;

    if (weather == null || weather.report.isMissing) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.help_outline),
        title: Text(label),
        trailing: Text(
          weather == null ? 'Unavailable offline' : 'No forecast',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final report = weather.report;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(weatherIcon(report.conditionBucket)),
      title: Text(label),
      subtitle: report.isEstimate
          ? Text('Seasonal average', style: theme.textTheme.bodySmall)
          : null,
      trailing: Text(formatRange(report), style: theme.textTheme.bodyLarge),
    );
  }
}
