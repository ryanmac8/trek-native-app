import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../calendar_feed/calendar_feed.dart';
import '../../calendar_feed/calendar_feed_repository.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/loading_indicator.dart';

/// Turns a Trek calendar feed on/off and subscribes the device calendar to
/// it. Shows the cached state immediately, then syncs in the background.
class CalendarFeedScreen extends ConsumerStatefulWidget {
  const CalendarFeedScreen({super.key, required this.scope});

  final CalendarFeedScope scope;

  @override
  ConsumerState<CalendarFeedScreen> createState() => _CalendarFeedScreenState();
}

class _CalendarFeedScreenState extends ConsumerState<CalendarFeedScreen> {
  CalendarFeedSnapshot? _snapshot;
  CalendarFeedSyncStatus? _status;
  bool _busy = false;

  CalendarFeedRepository get _repository =>
      ref.read(calendarFeedRepositoryProvider);

  bool get _isTrip => widget.scope is TripFeedScope;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _repository.readCached(widget.scope);
    if (!mounted) return;
    if (cached != null) setState(() => _snapshot = cached);
    await _refresh();
  }

  Future<void> _refresh() => _run(() => _repository.refresh(widget.scope));

  Future<void> _run(Future<CalendarFeedSyncResult> Function() body) async {
    setState(() => _busy = true);
    final CalendarFeedSyncResult result;
    try {
      result = await body();
    } on Exception {
      // Local storage failure — nothing was synced or cached.
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.showError('Could not update the feed.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _snapshot = result.snapshot;
      _status = result.status;
    });
    if (result.status == CalendarFeedSyncStatus.failed) {
      AppMessenger.showError(result.message ?? 'Could not update the feed.');
    }
  }

  Future<void> _requestAction(CalendarFeedAction action) async {
    // Reflect the change straight away; the repository persists it before
    // touching the network.
    setState(
      () => _snapshot = (_snapshot ?? CalendarFeedSnapshot.empty).withPending(
        action,
      ),
    );
    await _run(() => _repository.request(widget.scope, action));
    if (_status == CalendarFeedSyncStatus.offline) {
      AppMessenger.showInfo("You're offline — this will sync when you retry.");
    }
  }

  Future<void> _toggle(bool on) async {
    if (on) return _requestAction(CalendarFeedAction.enable);
    final confirmed = await _confirm(
      title: 'Turn off calendar feed?',
      message:
          'Calendars already subscribed to this feed will stop updating and '
          'its link will stop working.',
      confirmLabel: 'Turn off',
    );
    if (confirmed) await _requestAction(CalendarFeedAction.disable);
  }

  Future<void> _rotate() async {
    final confirmed = await _confirm(
      title: 'Reset link?',
      message:
          'A new link will be created. Every calendar subscribed to the '
          'current link — on any device, by anyone — will stop updating.',
      confirmLabel: 'Reset',
    );
    if (confirmed) await _requestAction(CalendarFeedAction.rotate);
  }

  Future<void> _subscribe(String url) async {
    final subscribed = await ref
        .read(calendarSubscriberProvider)
        .subscribe(url);
    if (subscribed) return;
    await Clipboard.setData(ClipboardData(text: url));
    AppMessenger.showInfo(
      'No calendar app could open the link, so it was copied — add it to '
      'your calendar as a subscription.',
    );
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    AppMessenger.showSuccess('Link copied.');
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isTrip ? 'Trip calendar sync' : 'Calendar sync'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final snapshot = _snapshot;
    if (_status == CalendarFeedSyncStatus.forbidden) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message:
            'Only people who can manage sharing for this trip can turn on '
            'its calendar feed.',
      );
    }
    if (snapshot == null) {
      if (_status == CalendarFeedSyncStatus.offline) {
        return EmptyState(
          icon: Icons.cloud_off,
          message:
              "You're offline. Calendar sync settings need a connection "
              'the first time.',
          action: OutlinedButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Retry'),
          ),
        );
      }
      return const LoadingIndicator();
    }

    final textTheme = Theme.of(context).textTheme;
    final url = snapshot.subscribableUrl;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            _isTrip
                ? "Subscribe your device's calendar to this trip's "
                      'itinerary. Your calendar app re-checks the feed about '
                      'once an hour, so changes show up on their own.'
                : "Subscribe your device's calendar to all your current and "
                      'upcoming trips. Your calendar app re-checks the feed '
                      'about once an hour, so changes show up on their own.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_status == CalendarFeedSyncStatus.offline) ...[
            _Banner(
              icon: Icons.cloud_off,
              text: snapshot.pending == null
                  ? "Offline — showing the last saved state."
                  : 'Offline — ${_pendingLabel(snapshot.pending!)} once '
                        'the server is reachable.',
              onRetry: _busy ? null : _refresh,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Calendar feed'),
              subtitle: Text(
                snapshot.isEnabled ? 'On' : 'Off',
                key: const Key('calendar-feed-state'),
              ),
              value: snapshot.isEnabled,
              onChanged: _busy ? null : _toggle,
            ),
          ),
          if (snapshot.isEnabled) ...[
            const SizedBox(height: AppSpacing.md),
            if (url == null)
              Text(
                'The subscription link will appear once this syncs with your '
                'server.',
                style: textTheme.bodyMedium,
              )
            else ...[
              AppCard(child: SelectableText(url, style: textTheme.bodySmall)),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => _subscribe(url),
                icon: const Icon(Icons.event_available),
                label: const Text('Add to calendar'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _copy(url),
                icon: const Icon(Icons.copy),
                label: const Text('Copy link'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _busy ? null : _rotate,
                child: const Text('Reset link'),
              ),
              Text(
                'Anyone with this link can see the itinerary. Reset it if it '
                'was shared by mistake.',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _pendingLabel(CalendarFeedAction action) => switch (action) {
    CalendarFeedAction.enable => 'the feed will turn on',
    CalendarFeedAction.rotate => 'the link will be reset',
    CalendarFeedAction.disable => 'the feed will turn off on the server',
  };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
