import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/widgets/loading_indicator.dart';
import 'providers.dart';

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
  late final Future<void> _restoreSession;

  @override
  void initState() {
    super.initState();
    _restoreSession = ref.read(authServiceProvider).restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _restoreSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            title: 'Trek',
            home: Scaffold(body: LoadingIndicator()),
          );
        }
        return MaterialApp.router(
          title: 'Trek',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          routerConfig: ref.watch(appRouterProvider),
        );
      },
    );
  }
}
