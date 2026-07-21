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

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([
      ref.read(authServiceProvider).restoreSession(),
      Future.delayed(_minSplashDuration),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(title: 'Trek', home: SplashScreen());
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
