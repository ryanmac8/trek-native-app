import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// The app's single [ScaffoldMessengerState], wired into `MaterialApp.router`
/// in [TrekApp]. Lets [AppMessenger] show snackbars from anywhere — screens
/// and services alike — without each screen wiring up its own Scaffold/
/// SnackBar handling, and without services needing a [BuildContext] at all.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum AppMessageType { error, success, info }

/// The one place screens and services should reach for a transient
/// user-facing message (a background sync failure, a completed action,
/// a heads-up). Errors with a natural spot in the UI — a form validation
/// message next to its field — should stay inline instead; this is for
/// messages with no such spot.
abstract final class AppMessenger {
  static void showError(String message) => _show(message, AppMessageType.error);

  static void showSuccess(String message) =>
      _show(message, AppMessageType.success);

  static void showInfo(String message) => _show(message, AppMessageType.info);

  static const _maxMountRetries = 5;

  static void _show(String message, AppMessageType type, [int retry = 0]) {
    final messengerState = scaffoldMessengerKey.currentState;
    // No app shell mounted yet (e.g. called before the first frame) — drop
    // rather than crash; there's nowhere to show it yet.
    if (messengerState == null) return;

    final color = switch (type) {
      AppMessageType.error => AppColors.danger,
      AppMessageType.success => AppColors.success,
      AppMessageType.info => AppColors.info,
    };

    try {
      messengerState
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      // ScaffoldMessenger.showSnackBar requires a mounted Scaffold
      // descendant — right after startup, go_router's redirect is still
      // resolving asynchronously and no route (hence no Scaffold) has
      // mounted yet. Retry a few frames rather than lose the message.
      if (retry >= _maxMountRetries) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _show(message, type, retry + 1),
      );
    }
  }
}
