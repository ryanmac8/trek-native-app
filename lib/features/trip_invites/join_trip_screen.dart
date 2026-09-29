import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/loading_indicator.dart';
import '../../network/api_exception.dart';
import 'trip_invite_repository.dart';

/// Opened from a trip invite link (`/join/:token`): shows which trip the
/// invite is for and lets the signed-in user join it or decline.
///
/// Offline, the user can still confirm — the join is queued locally (see
/// [TripInviteRepository]) and sent once the server is reachable.
class JoinTripScreen extends ConsumerStatefulWidget {
  const JoinTripScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends ConsumerState<JoinTripScreen> {
  late Future<InviteLookup> _lookup;
  bool _submitting = false;

  TripInviteRepository get _repository =>
      ref.read(tripInviteRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _lookup = _repository.lookup(widget.token);
  }

  void _retry() {
    setState(() => _lookup = _repository.lookup(widget.token));
  }

  Future<void> _join() async {
    setState(() => _submitting = true);
    final JoinOutcome outcome;
    try {
      outcome = await _repository.accept(widget.token);
    } on UnauthorizedException {
      // The session is gone; the router is already redirecting to login and
      // the invite is remembered for afterwards.
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (outcome) {
      case JoinCompleted(:final tripId, :final joined):
        AppMessenger.showSuccess(
          joined ? 'You joined the trip.' : 'You already have this trip.',
        );
        context.go('/trips/$tripId');
      case JoinQueued():
        AppMessenger.showInfo(
          "You're offline. You'll join this trip once you're back online.",
        );
        context.go('/trips');
      case JoinInvalid(:final message):
        AppMessenger.showError(message);
        context.go('/trips');
      case JoinFailed(:final message):
        AppMessenger.showError(message);
    }
  }

  Future<void> _decline() async {
    await _repository.discard(widget.token);
    if (mounted) context.go('/trips');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip invite')),
      body: FutureBuilder<InviteLookup>(
        future: _lookup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              message: '${snapshot.error}',
              action: TextButton(onPressed: _retry, child: const Text('Retry')),
            );
          }
          final lookup = snapshot.data;
          if (lookup == null) return const LoadingIndicator();
          return switch (lookup) {
            InviteFound(:final title) => _InvitePrompt(
              message: "You've been invited to join",
              title: title,
              submitting: _submitting,
              onJoin: _join,
              onDecline: _decline,
            ),
            InviteOffline(:final cached) => _InvitePrompt(
              message:
                  "You're offline, so this invite can't be checked yet. "
                  "Confirm now and you'll join once you're back online.",
              title: cached?.tripTitle,
              submitting: _submitting,
              onJoin: _join,
              onDecline: _decline,
              onRetry: _retry,
            ),
            InviteInvalid(:final message) => EmptyState(
              icon: Icons.link_off,
              message: message,
              action: FilledButton(
                onPressed: () => context.go('/trips'),
                child: const Text('Back to trips'),
              ),
            ),
            InviteLookupFailed(:final message) => EmptyState(
              icon: Icons.error_outline,
              message: message,
              action: TextButton(onPressed: _retry, child: const Text('Retry')),
            ),
          };
        },
      ),
    );
  }
}

class _InvitePrompt extends StatelessWidget {
  const _InvitePrompt({
    required this.message,
    required this.title,
    required this.submitting,
    required this.onJoin,
    required this.onDecline,
    this.onRetry,
  });

  final String message;
  final String? title;
  final bool submitting;
  final VoidCallback onJoin;
  final VoidCallback onDecline;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = this.title;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_add, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            if (title != null && title.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: submitting ? null : onJoin,
              child: const Text('Join trip'),
            ),
            TextButton(
              onPressed: submitting ? null : onDecline,
              child: const Text('Not now'),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: submitting ? null : onRetry,
                child: const Text('Check again'),
              ),
          ],
        ),
      ),
    );
  }
}
