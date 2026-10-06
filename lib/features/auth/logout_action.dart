import 'package:flutter/material.dart';

import '../../app/app_messenger.dart';
import '../../auth/auth_service.dart';

/// Logs out of [authService], which also clears all account-scoped local
/// data. If any local changes haven't synced to the server yet, asks for
/// confirmation first, since logging out discards them. Returns whether the
/// logout went ahead.
Future<bool> confirmAndLogout(
  BuildContext context,
  AuthService authService,
) async {
  final unsynced = await authService.localData.unsyncedChangeCount();
  if (unsynced > 0) {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsynced changes?'),
        content: Text(
          unsynced == 1
              ? '1 change made on this device hasn\'t reached the server '
                    'yet. Logging out deletes it.'
              : '$unsynced changes made on this device haven\'t reached '
                    'the server yet. Logging out deletes them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out anyway'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }

  await authService.logout();
  AppMessenger.showInfo('Logged out.');
  return true;
}
