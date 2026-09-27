import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../sync/sync_status.dart';

/// App-bar action showing whether local changes are waiting to reach the
/// server. Hidden when the outbox is empty and nothing is syncing; tapping
/// it retries immediately and explains the current state.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    if (status.phase == SyncPhase.idle && !status.hasPending) {
      return const SizedBox.shrink();
    }

    final icon = switch (status.phase) {
      SyncPhase.syncing => Icons.sync,
      SyncPhase.offline => Icons.cloud_off,
      SyncPhase.retrying => Icons.cloud_sync,
      SyncPhase.authRequired => Icons.sync_problem,
      SyncPhase.idle => Icons.cloud_upload,
    };
    final message = describeSyncStatus(status);

    return IconButton(
      tooltip: message,
      icon: Badge.count(
        count: status.pendingCount,
        isLabelVisible: status.hasPending,
        child: Icon(icon),
      ),
      onPressed: () {
        unawaited(ref.read(syncEngineProvider).drain());
        AppMessenger.showInfo(message);
      },
    );
  }
}

/// User-facing summary of [status], used as the indicator's tooltip.
String describeSyncStatus(SyncStatus status) {
  final count = status.pendingCount;
  final changes = count == 1 ? '1 change' : '$count changes';
  return switch (status.phase) {
    SyncPhase.syncing => 'Syncing $changes…',
    SyncPhase.offline => 'Offline — $changes will sync when reconnected.',
    SyncPhase.retrying => 'Server error — retrying $changes shortly.',
    SyncPhase.authRequired => 'Log in again to sync $changes.',
    SyncPhase.idle => '$changes waiting to sync.',
  };
}
