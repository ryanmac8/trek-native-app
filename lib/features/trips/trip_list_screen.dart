import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/widgets/empty_state.dart';

/// Landing screen once a session is active. Trips themselves aren't wired
/// up yet (issue #3) — this establishes the navigation shell and an
/// explicit empty state rather than faking data.
class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => ref.read(authServiceProvider).logout(),
          ),
        ],
      ),
      body: const EmptyState(icon: Icons.card_travel, message: 'No trips yet.'),
    );
  }
}
