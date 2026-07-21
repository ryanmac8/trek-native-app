import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../trips/trip.dart';

/// Landing screen once a session is active. Reads are network-only for now
/// — no local cache yet (that's #21's job) — so per docs/offline-first.md
/// this must degrade explicitly rather than hang or crash: a
/// [NetworkException] shows an offline state with retry, not an infinite
/// spinner or an uncaught error. A 401 doesn't show an error here at all —
/// `ApiClient.onUnauthorized` already flagged `AuthService.needsReconnect`,
/// which the surrounding `SyncStatusShell` banner surfaces; this screen
/// just falls back to its empty state rather than duplicating that message.
class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  late Future<List<Trip>> _tripsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final future = ref.read(tripsApiProvider).listTrips();
    // FutureBuilder attaches its own listener on the next build, which can
    // be a frame after this future is created — if it rejects before then
    // (routine with a fast/mocked backend), Dart's zone reports it as an
    // unhandled error even though FutureBuilder goes on to render it fine.
    // This sink doesn't affect FutureBuilder's own handling below — each
    // listener on a Future is independent.
    future.catchError((_) => const <Trip>[]);
    _tripsFuture = future;
  }

  Future<void> _refresh() async {
    setState(_load);
    await _tripsFuture.catchError((_) => <Trip>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await ref.read(authServiceProvider).logout();
              AppMessenger.showInfo('Logged out.');
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Trip>>(
        future: _tripsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: const [
                SkeletonListTile(),
                SkeletonListTile(),
                SkeletonListTile(),
              ],
            );
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is NetworkException) {
              return EmptyState(
                icon: Icons.cloud_off,
                message:
                    "You're offline. Trips will load once you're "
                    'back online.',
                action: FilledButton(
                  onPressed: () => setState(_load),
                  child: const Text('Retry'),
                ),
              );
            }
            if (error is UnauthorizedException) {
              // AuthService.needsReconnect is already set by ApiClient's
              // onUnauthorized callback; SyncStatusShell surfaces that.
              // Nothing trip-specific to say here.
              return const EmptyState(
                icon: Icons.card_travel,
                message: 'No trips yet.',
              );
            }
            return EmptyState(
              icon: Icons.error_outline,
              message: "Couldn't load trips.",
              action: FilledButton(
                onPressed: () => setState(_load),
                child: const Text('Retry'),
              ),
            );
          }

          final trips = snapshot.data ?? const [];
          if (trips.isEmpty) {
            return const EmptyState(
              icon: Icons.card_travel,
              message: 'No trips yet.',
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];
                return AppListRow(
                  title: trip.title,
                  subtitle: _dateRangeLabel(trip),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/trips/${trip.id}'),
                );
              },
            ),
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
