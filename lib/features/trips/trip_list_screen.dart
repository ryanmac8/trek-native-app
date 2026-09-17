import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/widgets/app_list_row.dart';
import 'trip_models.dart';

/// Landing screen once a session is active.
///
/// Shows the user's list of trips with options to create a new trip.
/// Each trip is tappable to navigate to the trip dashboard.
class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverConfig = ref.watch(serverConfigStorageProvider);
    final allTrips = ref.watch(tripLocalStoreProvider);

    final showServerSetup = !serverConfig.hasServer;

    if (showServerSetup) {
      return _ServerSetupScreen();
    }

    if (allTrips.isEmpty) {
      return _EmptyStateScreen();
    }

    return _TripListScreen(trips: allTrips, onAdd: () {
      context.push('/trips');
    });
  }
}

class _ServerSetupScreen extends StatelessWidget {
  const _ServerSetupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Server configuration required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Please configure your Trek server URL',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => context.go('/server-setup'),
                icon: const Icon(Icons.wifi),
                label: const Text('Configure Server'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStateScreen extends StatelessWidget {
  const _EmptyStateScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.wb_cloudy_outlined),
            tooltip: 'Weather',
            onPressed: () => context.push('/weather'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.directions_transit),
            tooltip: 'Transit',
            onPressed: () => context.push('/transit'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Trip',
            onPressed: () => context.push('/trips/new'),
          ),
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
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.card_travel,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No trips yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Create your first trip to get started',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 24),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.green),
              onPressed: () => Navigator.of(context).push('/trips/new'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripListScreen extends StatelessWidget {
  final List<Trip> trips;
  final VoidCallback onAdd;

  const _TripListScreen({
    required this.trips,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.wb_cloudy_outlined),
            tooltip: 'Weather',
            onPressed: () => context.push('/weather'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.directions_transit),
            tooltip: 'Transit',
            onPressed: () => context.push('/transit'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Trip',
            onPressed: () => onAdd,
          ),
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
      body: RepaintData(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        itemCount: trips.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final trip = trips[index];
          return _TripListTile(trip: trip);
        },
      ),
    );
  }
}

class RepaintData extends StatelessWidget {
  const RepaintData({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary();
  }
}

class _TripListTile extends StatelessWidget {
  final Trip trip;

  const _TripListTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(trip.id),
      direction: DismissDirection.endToEnd,
      background: _DeleteBackground(),
      onDismissed: (direction) async {
        // Delete trip
        // TODO: Implement
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Trip deleted'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: ListTile(
        title: Text(
          trip.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trip.description?.isNotEmpty == true) ...[
              Text(
                trip.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (trip.tags.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: trip.tags
                    .map((tag) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Chip(
                            label: Text(tag),
                            backgroundColor: Colors.grey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '${trip.createdAt} • ${trip.visibility}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            // Edit trip
            // TODO: Implement
          },
        ),
        onTap: () {
          // Navigate to trip dashboard
          // TODO: Implement
        },
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.red,
      child: const Center(
        child: Icon(Icons.delete, color: Colors.white),
      ),
    );
  }
}
