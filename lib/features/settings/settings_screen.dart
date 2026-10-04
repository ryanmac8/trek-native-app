import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';

/// Settings hub — a list of sub-pages, matching the pattern self-hosted
/// apps like Immich use rather than one long flat form. "Networking" is a
/// sub-page; "App lock" is an inline switch since it's a single on/off
/// choice. More rows (account, appearance, etc.) belong here as they're
/// built, not guessed at now. Logout lives in this AppBar rather
/// than the trip list's — it's an account-level action, not a trip one.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await ref.read(authServiceProvider).logout();
              AppMessenger.showInfo('Logged out.');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          AppListRow(
            leading: const Icon(Icons.wifi),
            title: 'Networking',
            subtitle: 'Server address, local network',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/networking'),
          ),
          const _AppLockRow(),
        ],
      ),
    );
  }
}

/// Turns the biometric app lock on or off (see `AppLockState.lockEnabled`).
/// Entirely local — the choice is stored on the device and never touches
/// the network. Turning it on first requires a successful biometric (or
/// device passcode) prompt, so the user can't enable a lock they then
/// can't get past. Disabled when the device has no biometrics set up.
class _AppLockRow extends ConsumerStatefulWidget {
  const _AppLockRow();

  @override
  ConsumerState<_AppLockRow> createState() => _AppLockRowState();
}

class _AppLockRowState extends ConsumerState<_AppLockRow> {
  bool _busy = false;

  Future<void> _setEnabled(bool enabled) async {
    final appLockState = ref.read(appLockStateProvider);
    setState(() => _busy = true);
    try {
      if (enabled) {
        final verified = await ref
            .read(biometricAuthServiceProvider)
            .authenticate();
        if (!verified) {
          AppMessenger.showError('Could not verify. App lock is still off.');
          return;
        }
      }
      try {
        await ref.read(appLockPreferenceStorageProvider).writeEnabled(enabled);
      } catch (error) {
        debugPrint('Settings: saving app lock preference failed: $error');
        AppMessenger.showError('Could not save the app lock setting.');
        return;
      }
      // Already inside the app, so turning the lock on shouldn't bounce
      // the user straight to /lock — the prompt above just verified them.
      if (enabled) appLockState.isUnlocked.value = true;
      appLockState.lockEnabled.value = enabled;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLockState = ref.watch(appLockStateProvider);
    final available = appLockState.biometricsAvailable;
    final textTheme = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: appLockState.lockEnabled,
      builder: (context, lockEnabled, _) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.fingerprint),
        title: Text('App lock', style: textTheme.titleMedium),
        subtitle: Text(
          available
              ? 'Require Face ID, Touch ID or fingerprint to open Trek'
              : 'Set up Face ID, Touch ID or a fingerprint on this device '
                    'to use app lock',
          style: textTheme.bodyMedium,
        ),
        value: available && lockEnabled,
        onChanged: available && !_busy ? _setEnabled : null,
      ),
    );
  }
}
