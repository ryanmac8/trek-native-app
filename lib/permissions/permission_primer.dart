import 'package:flutter/material.dart';

import 'app_permission.dart';
import 'permission_gateway.dart';
import 'priming_sheet.dart';
import 'priming_storage.dart';

/// How a [PermissionPrimer.ensure] call ended.
enum PrimingOutcome {
  /// Already granted, or granted at the OS prompt.
  granted,

  /// The user tapped "Not now" on the priming sheet; the OS prompt was
  /// never shown, so it's still available next time.
  dismissed,

  /// The user saw the OS prompt and refused it.
  denied,

  /// The OS won't prompt any more (permanently denied / restricted).
  blocked,

  /// Not asked: an automatic prime within [PermissionPrimer.cooldown] of
  /// the user's last "Not now".
  snoozed,
}

/// Shows an in-app explanation before the OS permission prompt, so the
/// one-shot system dialog is only spent once the user has opted in.
///
/// Flow for [ensure]:
/// 1. Already granted → [PrimingOutcome.granted], no UI.
/// 2. Blocked by the OS → a "turn it on in Settings" sheet if
///    `userInitiated`, otherwise nothing ([PrimingOutcome.blocked]).
/// 3. Not user-initiated and "Not now" was tapped within [cooldown] →
///    [PrimingOutcome.snoozed], no UI.
/// 4. Otherwise the priming sheet; "Continue" triggers the OS prompt,
///    "Not now" records the decline.
///
/// Entirely device-local — no network involved at any step.
class PermissionPrimer {
  PermissionPrimer({
    required PermissionGateway gateway,
    required PrimingStorage storage,
    DateTime Function()? clock,
    this.cooldown = const Duration(days: 14),
  }) : _gateway = gateway,
       _storage = storage,
       _clock = clock ?? DateTime.now;

  final PermissionGateway _gateway;
  final PrimingStorage _storage;
  final DateTime Function() _clock;

  /// How long an automatic prime stays quiet after "Not now".
  final Duration cooldown;

  /// Current OS status, with no UI.
  Future<AppPermissionStatus> status(AppPermission permission) =>
      _gateway.status(permission);

  /// Makes sure [permission] is granted, priming first if needed. Pass
  /// `userInitiated: true` when the user just turned on the feature that
  /// needs it (bypasses the "Not now" cooldown and explains a blocked
  /// permission instead of failing silently).
  Future<PrimingOutcome> ensure(
    BuildContext context,
    AppPermission permission, {
    bool userInitiated = false,
  }) async {
    final current = await _gateway.status(permission);
    if (current == AppPermissionStatus.granted) return PrimingOutcome.granted;

    if (current == AppPermissionStatus.permanentlyDenied ||
        current == AppPermissionStatus.restricted) {
      if (userInitiated && context.mounted) {
        final openSettings = await showPermissionBlockedSheet(
          context,
          permission,
          canOpenSettings: current == AppPermissionStatus.permanentlyDenied,
        );
        if (openSettings) await _gateway.openSettings();
      }
      return PrimingOutcome.blocked;
    }

    if (!userInitiated) {
      final declinedAt = await _storage.declinedAt(permission);
      if (declinedAt != null && _clock().difference(declinedAt) < cooldown) {
        return PrimingOutcome.snoozed;
      }
    }

    if (!context.mounted) return PrimingOutcome.dismissed;
    final proceed = await showPermissionPrimingSheet(context, permission);
    if (!proceed) {
      await _storage.recordDecline(permission, _clock());
      return PrimingOutcome.dismissed;
    }

    final result = await _gateway.request(permission);
    switch (result) {
      case AppPermissionStatus.granted:
        await _storage.clearDecline(permission);
        return PrimingOutcome.granted;
      case AppPermissionStatus.denied:
        return PrimingOutcome.denied;
      case AppPermissionStatus.permanentlyDenied:
      case AppPermissionStatus.restricted:
        return PrimingOutcome.blocked;
    }
  }
}
