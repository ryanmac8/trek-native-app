import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../maps/maps_models.dart';
import '../../maps/maps_repository.dart';
import '../../network/api_exception.dart';

/// The `/maps` screen, reachable from the trip list's app-bar map icon.
///
/// A first slice of maps/geocoding ([#17]) — resolving a pasted Google Maps
/// link and reverse-geocoding a manually entered coordinate into a
/// name/address. Both are read-only lookups shown for reference; turning a
/// result into a trip place needs place creation ([#5]), which this app
/// doesn't have yet, so there is no "add to trip" action here.
///
/// [#17]: https://github.com/ryanmac8/trek-native-app/issues/17
///
/// Reads go through [MapsRepository]: a cached answer paints immediately and
/// a failed refresh falls back to it behind an offline notice. See
/// docs/maps.md.
class MapsLookupScreen extends StatelessWidget {
  const MapsLookupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maps lookup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          _ResolveUrlSection(),
          SizedBox(height: AppSpacing.lg),
          _ReverseGeocodeSection(),
        ],
      ),
    );
  }
}

class _InlineSpinner extends StatelessWidget {
  const _InlineSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException
        ? (error as ApiException).message
        : 'Something went wrong.';
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

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
              'Showing a saved answer — offline.',
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

class _ResolveUrlSection extends ConsumerStatefulWidget {
  const _ResolveUrlSection();

  @override
  ConsumerState<_ResolveUrlSection> createState() => _ResolveUrlSectionState();
}

class _ResolveUrlSectionState extends ConsumerState<_ResolveUrlSection> {
  final _controller = TextEditingController();
  Future<ResolvedPlaceSnapshot>? _future;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      // FutureBuilder attaches its own listener once this rebuild runs, but
      // ignore() attaches one right away so a rejection (an offline lookup
      // with nothing cached, which is an expected outcome here, not a bug)
      // never gets reported as an unhandled zone error in the gap before
      // then.
      _future = ref.read(mapsRepositoryProvider).resolveUrl(url)..ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paste a Maps link', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Resolve a shared Google Maps link into a place.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'https://maps.app.goo.gl/...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _submit,
              child: const Text('Resolve'),
            ),
          ),
          if (_future != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: FutureBuilder<ResolvedPlaceSnapshot>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _InlineSpinner();
                  }
                  if (snapshot.hasError) {
                    return _ErrorText(error: snapshot.error);
                  }
                  return _ResolvedPlaceView(snapshot: snapshot.data!);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ResolvedPlaceView extends StatelessWidget {
  const _ResolvedPlaceView({required this.snapshot});

  final ResolvedPlaceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final place = snapshot.place;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (snapshot.stale) const _OfflineNotice(),
        Text(place.name ?? 'Unnamed place', style: theme.textTheme.titleSmall),
        if (place.address != null)
          Text(place.address!, style: theme.textTheme.bodySmall),
        Text(
          '${place.point.lat.toStringAsFixed(5)}, '
          '${place.point.lng.toStringAsFixed(5)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReverseGeocodeSection extends ConsumerStatefulWidget {
  const _ReverseGeocodeSection();

  @override
  ConsumerState<_ReverseGeocodeSection> createState() =>
      _ReverseGeocodeSectionState();
}

class _ReverseGeocodeSectionState
    extends ConsumerState<_ReverseGeocodeSection> {
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  Future<ReverseGeocodeSnapshot>? _future;
  String? _inputError;

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _submit() {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    final valid =
        lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    if (!valid) {
      setState(() => _inputError = 'Enter a valid latitude and longitude.');
      return;
    }
    setState(() {
      _inputError = null;
      // See the matching comment in _ResolveUrlSectionState._submit.
      _future =
          ref.read(mapsRepositoryProvider).reverseGeocode(LatLng(lat, lng))
            ..ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Look up a coordinate', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Reverse-geocode a manually pinned location into a name and '
            'address.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _lngController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (_inputError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _inputError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _submit,
              child: const Text('Look up'),
            ),
          ),
          if (_future != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: FutureBuilder<ReverseGeocodeSnapshot>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _InlineSpinner();
                  }
                  if (snapshot.hasError) {
                    return _ErrorText(error: snapshot.error);
                  }
                  final result = snapshot.data!;
                  if (result.result.isEmpty) {
                    return Text(
                      'No address found for that coordinate.',
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  return _ReverseGeocodeView(snapshot: result);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ReverseGeocodeView extends StatelessWidget {
  const _ReverseGeocodeView({required this.snapshot});

  final ReverseGeocodeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final result = snapshot.result;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (snapshot.stale) const _OfflineNotice(),
        if (result.name != null)
          Text(result.name!, style: theme.textTheme.titleSmall),
        if (result.address != null)
          Text(result.address!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
