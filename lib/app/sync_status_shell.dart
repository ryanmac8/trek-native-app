import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Wraps the authenticated routes (see `buildAppRouter`'s `ShellRoute`) with
/// a persistent, non-blocking banner shown while
/// [AuthService.needsReconnect] is set. Deliberately doesn't intercept
/// navigation or hide [child] — per this app's offline-first principle, a
/// broken connection to Trek is a "can't sync right now" notice, not a
/// reason to lock the user out of the app.
class SyncStatusShell extends StatelessWidget {
  const SyncStatusShell({
    super.key,
    required this.authService,
    required this.child,
  });

  final AuthService authService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: authService.needsReconnect,
      builder: (context, needsReconnect, _) {
        return Column(
          children: [
            if (needsReconnect) const _ReconnectBanner(),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warning,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.black87, size: 20),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  "Can't sync with Trek right now. Your changes are safe "
                  'locally.',
                  style: TextStyle(color: Colors.black87),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/reconnect'),
                child: const Text('Reconnect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
