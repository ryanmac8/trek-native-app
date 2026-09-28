import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../notification_preferences/notification_preferences_models.dart';

/// Which notifications Trek sends the signed-in user, over which channels
/// (first slice of issue #22): one card per event type with a switch per
/// channel that can deliver it, from `GET /api/notifications/preferences`.
///
/// Per docs/offline-first.md it reads and writes through
/// [NotificationPreferencesRepository]: the last-known matrix paints from
/// the local cache first, a toggle applies on the device immediately and
/// syncs in the background, and while offline the toggles keep working and
/// a banner says how many changes are waiting to sync. With nothing cached
/// and no connection, an explicit offline state with a retry is shown.
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  CachedNotificationPreferences? _prefs;
  Object? _error;
  bool _stale = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = ref.read(notificationPreferencesRepositoryProvider);

    // Paint the cached matrix first so the screen isn't blank while the
    // refresh runs.
    final cached = await repository.cached();
    if (mounted && cached != null && _prefs == null) {
      setState(() {
        _prefs = cached;
        _stale = true;
      });
    }

    try {
      final fresh = await repository.refresh();
      if (!mounted) return;
      setState(() {
        _prefs = fresh;
        _stale = false;
      });
    } catch (e) {
      if (!mounted) return;
      final latest = await repository.cached();
      if (!mounted) return;
      setState(() {
        // Keep showing the cached matrix (marked stale) if there is one;
        // otherwise surface the failure so the screen can offer a retry.
        _prefs = latest ?? _prefs;
        if (_prefs == null) {
          _error = e;
        } else {
          _stale = true;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String eventType, String channelId, bool enabled) async {
    final repository = ref.read(notificationPreferencesRepositoryProvider);
    final updated = await repository.setPreference(
      eventType,
      channelId,
      enabled,
    );
    if (!mounted) return;
    setState(() => _prefs = updated);
    await _sync();
  }

  Future<void> _sync() async {
    final repository = ref.read(notificationPreferencesRepositoryProvider);
    try {
      final synced = await repository.syncPending();
      if (!mounted || synced == null) return;
      setState(() {
        _prefs = synced;
        _stale = false;
      });
    } on NetworkException {
      // The change is saved on the device and stays pending; the banner
      // says so.
      if (mounted) setState(() => _stale = true);
    } on UnauthorizedException {
      // The session was cleared; the router redirects to login.
    } on ApiException catch (e) {
      AppMessenger.showError(
        "Couldn't save your notification preference: ${e.message}",
      );
      final latest = await repository.cached();
      if (mounted && latest != null) setState(() => _prefs = latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final prefs = _prefs;

    if (prefs == null && _loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 96),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 96),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 96),
        ],
      );
    }

    if (prefs == null) {
      final offline = _error is NetworkException;
      return _Scrollable(
        child: EmptyState(
          icon: offline ? Icons.cloud_off : Icons.error_outline,
          message: offline
              ? "You're offline, and your notification preferences haven't "
                    'been loaded yet.'
              : "Couldn't load your notification preferences.",
          action: FilledButton(onPressed: _load, child: const Text('Retry')),
        ),
      );
    }

    final matrix = prefs.matrix;
    final events = [
      for (final event in matrix.eventTypes)
        if (matrix.channelsFor(event).isNotEmpty) event,
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_stale && !_loading) ...[
          _StaleBanner(fetchedAt: prefs.fetchedAt, onRetry: _load),
          const SizedBox(height: AppSpacing.md),
        ],
        if (prefs.hasPending) ...[
          _PendingBanner(count: prefs.pendingCount),
          const SizedBox(height: AppSpacing.md),
        ],
        if (events.isEmpty)
          const EmptyState(
            icon: Icons.notifications_off_outlined,
            message:
                'No notification channels are configured. Ask an admin to '
                'set up email or webhook notifications.',
          ),
        for (final event in events) ...[
          _EventCard(
            eventType: event,
            matrix: matrix,
            onChanged: (channelId, enabled) =>
                _toggle(event, channelId, enabled),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.eventType,
    required this.matrix,
    required this.onChanged,
  });

  final String eventType;
  final NotificationPreferencesMatrix matrix;
  final void Function(String channelId, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              notificationEventLabel(eventType),
              style: textTheme.titleMedium,
            ),
          ),
          for (final channel in matrix.channelsFor(eventType))
            SwitchListTile(
              key: Key('pref-$eventType-${channel.id}'),
              title: Text(channel.displayLabel),
              subtitle: channel.configured
                  ? null
                  : const Text('Not configured yet'),
              value: matrix.isEnabled(eventType, channel.id),
              onChanged: (value) => onChanged(channel.id, value),
            ),
        ],
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: constraints.maxHeight, child: child),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.fetchedAt, required this.onRetry});

  final DateTime fetchedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final local = fetchedAt.toLocal();
    final date =
        '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Offline — showing preferences from $date.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final changes = count == 1 ? '1 change' : '$count changes';
    return AppCard(
      child: Row(
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$changes saved on this device, waiting to sync with your '
              'server.',
            ),
          ),
        ],
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
