import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../notifications/notification_text.dart';
import '../../notifications/trek_notification.dart';

/// The notifications inbox (first slice of issue #15). Per
/// docs/offline-first.md, the local cache
/// ([NotificationsRepository.cachedNotifications]) is the source of truth
/// for what's shown — this paints from it immediately, then refreshes from
/// the network in the background. Marking a notification read applies
/// locally first and syncs in the background (retried on the next
/// refresh), so it works offline.
///
/// This slice is list + mark-read only: no boolean yes/no responses, no
/// delete, no acting on a `navigate` notification's target (the native
/// routes it points at mostly don't exist yet), and no pagination.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<TrekNotification>? _notifications;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(notificationsRepositoryProvider);
    final cached = await repository.cachedNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(notificationsRepositoryProvider);
    try {
      final refreshed = await repository.refreshNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_notifications == null || _notifications!.isEmpty) _error = e;
      });
    }
  }

  Future<void> _markRead(int id) async {
    await ref.read(notificationsRepositoryProvider).markRead(id);
    if (!mounted) return;
    final current = _notifications;
    if (current != null) {
      setState(() {
        _notifications = [
          for (final n in current)
            if (n.id == id) n.copyWith(isRead: true) else n,
        ];
      });
    }
  }

  Future<void> _markAllRead() async {
    await ref.read(notificationsRepositoryProvider).markAllRead();
    if (!mounted) return;
    final current = _notifications;
    if (current != null) {
      setState(() {
        _notifications = [for (final n in current) n.copyWith(isRead: true)];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _notifications;
    final hasUnread = notifications?.any((n) => !n.isRead) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _body(notifications),
    );
  }

  Widget _body(List<TrekNotification>? notifications) {
    if (notifications == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (notifications.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message:
              "You're offline. Notifications will load once you're back "
              'online.',
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load notifications.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.notifications_none,
        message: "You're all caught up.",
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return _NotificationRow(
            notification: notification,
            onTap: notification.isRead
                ? null
                : () => _markRead(notification.id),
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, this.onTap});

  final TrekNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time = relativeTimeLabel(notification.createdAt);
    final body = notificationBody(notification);

    final subtitleParts = [if (body.isNotEmpty) body, ?time];

    return AppListRow(
      onTap: onTap,
      leading: Icon(
        notification.isRead
            ? Icons.notifications_none
            : Icons.notifications_active,
        color: notification.isRead ? null : colorScheme.primary,
      ),
      title: notificationTitle(notification),
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
      trailing: notification.isRead
          ? null
          : Icon(Icons.circle, size: 10, color: colorScheme.primary),
    );
  }
}
