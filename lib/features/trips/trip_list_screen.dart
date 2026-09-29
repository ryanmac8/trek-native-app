import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/widgets/empty_state.dart';
import '../../network/api_exception.dart';
import '../trip_invites/open_link_dialog.dart';
import '../trip_invites/trip_invite_repository.dart';

/// Landing screen once a session is active. Trips themselves aren't wired
/// up yet (issue #3) — this establishes the navigation shell and an
/// explicit empty state rather than faking data.
///
/// On open it sends any trip joins that were confirmed while offline (see
/// [TripInviteRepository.flushQueued]).
class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  @override
  void initState() {
    super.initState();
    _flushQueuedJoins();
  }

  Future<void> _flushQueuedJoins() async {
    final List<JoinOutcome> outcomes;
    try {
      outcomes = await ref.read(tripInviteRepositoryProvider).flushQueued();
    } on UnauthorizedException {
      return;
    } catch (error) {
      // A local storage failure only delays the queued joins to the next
      // time this screen opens; it shouldn't take the trip list down.
      debugPrint('TripListScreen: could not flush queued joins: $error');
      return;
    }
    for (final outcome in outcomes) {
      switch (outcome) {
        case JoinCompleted(:final joined, :final tripTitle) when joined:
          AppMessenger.showSuccess(
            tripTitle == null || tripTitle.isEmpty
                ? 'You joined a trip.'
                : 'You joined $tripTitle.',
          );
        case JoinInvalid():
          AppMessenger.showError(
            'A trip invite you accepted offline is no longer valid.',
          );
        case JoinCompleted() || JoinQueued() || JoinFailed():
          break;
      }
    }
  }

  Future<void> _openLink() async {
    final config = await ref.read(serverConfigStorageProvider).read();
    if (!mounted) return;
    final link = await showOpenLinkDialog(context, config: config);
    if (link != null && mounted) context.push(link.location);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Open a Trek link',
            onPressed: _openLink,
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
      body: const EmptyState(icon: Icons.card_travel, message: 'No trips yet.'),
    );
  }
}
