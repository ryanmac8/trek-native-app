import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';

/// Shown when there's an active session but the app hasn't been unlocked
/// via biometrics yet this run (see `AppLockState`, `buildAppRouter`).
/// Prompts automatically on first appearance; success flips
/// `AppLockState.isUnlocked`, which the router picks up on its own via
/// `refreshListenable` — this screen never navigates itself.
class BiometricLockScreen extends ConsumerStatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  ConsumerState<BiometricLockScreen> createState() =>
      _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  bool _isAuthenticating = false;
  bool _lastAttemptFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _lastAttemptFailed = false;
    });

    final succeeded = await ref
        .read(biometricAuthServiceProvider)
        .authenticate();

    if (!mounted) return;
    if (succeeded) {
      ref.read(appLockStateProvider).isUnlocked.value = true;
      return;
    }
    setState(() {
      _isAuthenticating = false;
      _lastAttemptFailed = true;
    });
  }

  Future<void> _logOutInstead() async {
    await ref.read(authServiceProvider).logout();
    AppMessenger.showInfo('Logged out.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fingerprint, size: 72, color: Colors.white70),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Trek is locked',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_lastAttemptFailed)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'Authentication failed or was cancelled.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _isAuthenticating ? null : _unlock,
                  child: _isAuthenticating
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Unlock'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _isAuthenticating ? null : _logOutInstead,
                  child: const Text(
                    'Log out instead',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
