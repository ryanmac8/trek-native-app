import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import 'app_permission.dart';

/// The pre-prompt explanation. Resolves to `true` for "Continue" (go on to
/// the OS prompt) and `false` for "Not now" or a swipe-away.
Future<bool> showPermissionPrimingSheet(
  BuildContext context,
  AppPermission permission,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    // Lets the sheet grow past the default half-screen cap (landscape,
    // large text) — the content scrolls once it hits the top.
    isScrollControlled: true,
    builder: (context) => _PermissionSheet(
      permission: permission,
      message: permission.rationale,
      primaryLabel: 'Continue',
      secondaryLabel: 'Not now',
    ),
  );
  return result ?? false;
}

/// Shown when the OS will no longer prompt. Resolves to `true` when the
/// user chose "Open Settings". With `canOpenSettings: false` (restricted —
/// device management, not the user, controls it) only a dismiss button is
/// offered.
Future<bool> showPermissionBlockedSheet(
  BuildContext context,
  AppPermission permission, {
  required bool canOpenSettings,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    // Lets the sheet grow past the default half-screen cap (landscape,
    // large text) — the content scrolls once it hits the top.
    isScrollControlled: true,
    builder: (context) => _PermissionSheet(
      permission: permission,
      message: permission.blockedMessage,
      primaryLabel: canOpenSettings ? 'Open Settings' : null,
      secondaryLabel: canOpenSettings ? 'Not now' : 'OK',
    ),
  );
  return result ?? false;
}

class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({
    required this.permission,
    required this.message,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final AppPermission permission;
  final String message;
  final String? primaryLabel;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(permission.icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              permission.title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (primaryLabel != null) ...[
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(primaryLabel!),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
