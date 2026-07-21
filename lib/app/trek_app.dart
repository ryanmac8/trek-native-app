import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import 'app_messenger.dart';
import 'providers.dart';
import 'splash_screen.dart';

/// Minimum time [SplashScreen] stays on screen, so its reveal animation
/// always gets to play even though [AuthService.restoreSession] is a fast
/// local-only read that alone would resolve almost instantly.
const _minSplashDuration = Duration(milliseconds: 1400);

/// Root widget. Restores the persisted session (a local-only read — see
/// `AuthService.currentAccessToken`) before building the router, so the
/// first navigation redirect reflects real auth state instead of the
/// `isAuthenticated` default of `false`.
class TrekApp extends ConsumerStatefulWidget {
  const TrekApp({super.key});

  @override
  ConsumerState<TrekApp> createState() => _TrekAppState();
}

class _TrekAppState extends ConsumerState<TrekApp> {
  late final Future<void> _startup;

  // Set only if restoreSession throws; consumed (and cleared) the first
  // time build() reaches the router phase, via a post-frame callback so
  // AppMessenger fires against the router's persistent ScaffoldMessenger
  // rather than the splash phase's, which is torn down the moment startup
  // completes and would otherwise silently drop the message.
  Object? _startupError;

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<void> _initialize() async {
    // BiometricAuthService.isAvailable() never throws (see its doc comment),
    // so this can't affect the error handling below — safe to resolve
    // before the restoreSession/min-duration pair.
    final biometricsAvailable = await ref
        .read(biometricAuthServiceProvider)
        .isAvailable();
    ref.read(appLockStateProvider).biometricsAvailable = biometricsAvailable;

    try {
      // Future.wait (default eagerError: false) waits for BOTH before
      // completing, so the minimum splash duration is honored even if
      // restoreSession throws.
      await Future.wait([
        ref.read(authServiceProvider).restoreSession(),
        Future.delayed(_minSplashDuration),
      ]);
    } catch (error, stackTrace) {
      // Fail closed: isAuthenticated stays at its default false, so the
      // user lands on /login rather than the app hanging or crashing.
      // restoreSession is a best-effort local read (see
      // AuthService.currentAccessToken) — flutter_secure_storage is known
      // to throw in the wild (Keychain access after a backup restore,
      // Keystore invalidated by a biometric/lock-screen change), so this
      // has to degrade gracefully rather than propagate.
      debugPrint('TrekApp: session restore failed: $error\n$stackTrace');
      _startupError = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(title: 'Trek', home: SplashScreen());
        }
        if (_startupError != null) {
          _startupError = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppMessenger.showError(
              'Could not restore your session. Please log in.',
            );
          });
        }
        return MaterialApp.router(
          title: 'Trek',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: ref.watch(appRouterProvider),
        );
      },
    );
  }
}
