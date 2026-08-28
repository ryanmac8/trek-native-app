import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/place_category_colors.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../reservations/reservation.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo/bookings sections the issue #2 nav structure calls for.
/// Bookings (the first slice of issue #11) reads real data; the rest are
/// still placeholders — none of those data models exist yet (issues #4–#9).
class TripDashboardScreen extends StatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripDashboardScreen> createState() => _TripDashboardScreenState();
}

class _TripDashboardScreenState extends State<TripDashboardScreen> {
  int _tabIndex = 0;

  static const _tabs = [
    (label: 'Days', icon: Icons.calendar_today),
    (label: 'Places', icon: Icons.place),
    (label: 'Budget', icon: Icons.attach_money),
    (label: 'Packing', icon: Icons.checklist),
    (label: 'Todos', icon: Icons.task_alt),
    (label: 'Bookings', icon: Icons.event_note),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip ${widget.tripId}')),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const _ComingSoonTab(label: 'Days'),
          const _PlacesPreviewTab(),
          const _ComingSoonTab(label: 'Budget'),
          const _ComingSoonTab(label: 'Packing'),
          const _ComingSoonTab(label: 'Todos'),
          _BookingsTab(tripId: widget.tripId),
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

/// The Places tab has no data yet, but doubles as a visual check of the
/// category color/icon tokens ([PlaceCategory]) against Trek's real
/// category list.
class _PlacesPreviewTab extends StatelessWidget {
  const _PlacesPreviewTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Places — coming soon',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final category in PlaceCategory.values)
              Chip(
                avatar: CircleAvatar(
                  backgroundColor: category.color,
                  child: Text(
                    category.icon,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                label: Text(category.label),
              ),
          ],
        ),
      ],
    );
  }
}

/// The Bookings tab: per docs/offline-first.md, the local cache
/// ([ReservationsRepository.cachedReservations]) is the source of truth for
/// what's shown — this paints from it immediately, then refreshes from the
/// network in the background. A [NetworkException] only surfaces as an
/// explicit offline state when there's nothing cached yet; if bookings are
/// already on screen, a failed background refresh just leaves them be.
///
/// This first slice of issue #11 is read-only: no create/edit/delete, no
/// day/place picker, no multi-leg transport detail, and no itinerary-day
/// context — those depend on the place pool (issue #5) and day model
/// (issue #4), neither of which is modeled client-side yet.
class _BookingsTab extends ConsumerStatefulWidget {
  const _BookingsTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<_BookingsTab> {
  List<Reservation>? _reservations;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(reservationsRepositoryProvider);
    final cached = await repository.cachedReservations(widget.tripId);
    if (!mounted) return;
    setState(() {
      _reservations = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(reservationsRepositoryProvider);
    try {
      final refreshed = await repository.refreshReservations(widget.tripId);
      if (!mounted) return;
      setState(() {
        _reservations = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_reservations == null || _reservations!.isEmpty) _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservations = _reservations;

    if (reservations == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (reservations.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message:
              "You're offline. Bookings will load once you're back online.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load bookings.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.event_note,
        message: 'No reservations yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: reservations.length,
        itemBuilder: (context, index) {
          final reservation = reservations[index];
          return AppListRow(
            leading: Icon(_typeIcon(reservation.type)),
            title: reservation.title,
            subtitle: _subtitle(reservation),
            trailing: _hasText(reservation.confirmationNumber)
                ? const Icon(Icons.confirmation_number_outlined, size: 18)
                : null,
          );
        },
      ),
    );
  }

  /// A start-time line when the user entered one, otherwise the location,
  /// otherwise the linked place, otherwise the itinerary day. A cancelled
  /// booking is prefixed so it reads as struck from the plan.
  String? _subtitle(Reservation reservation) {
    final parts = <String>[];
    if (reservation.status == 'cancelled') parts.add('Cancelled');

    final detail =
        _firstText([
          reservation.reservationTime,
          reservation.location,
          reservation.placeName,
        ]) ??
        (reservation.dayNumber != null ? 'Day ${reservation.dayNumber}' : null);
    if (detail != null) parts.add(detail);

    return parts.isEmpty ? null : parts.join(' · ');
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String? _firstText(List<String?> candidates) {
    for (final candidate in candidates) {
      if (_hasText(candidate)) return candidate;
    }
    return null;
  }

  /// Maps Trek's free-form reservation `type` onto a Material icon, with a
  /// generic fallback for anything unrecognized.
  static IconData _typeIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'flight':
      case 'plane':
        return Icons.flight;
      case 'train':
        return Icons.train;
      case 'bus':
        return Icons.directions_bus;
      case 'car':
      case 'car-rental':
      case 'transfer':
        return Icons.directions_car;
      case 'ferry':
      case 'boat':
        return Icons.directions_boat;
      case 'taxi':
        return Icons.local_taxi;
      case 'hotel':
      case 'accommodation':
      case 'lodging':
        return Icons.hotel;
      case 'restaurant':
        return Icons.restaurant;
      case 'activity':
      case 'tour':
      case 'event':
        return Icons.local_activity;
      case 'parking':
        return Icons.local_parking;
      default:
        return Icons.event_note;
    }
  }
}
