import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../config/server_config.dart';
import '../features/auth/biometric_lock_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/mfa_screen.dart';
import '../features/auth/reconnect_screen.dart';
import '../features/server_setup/server_setup_screen.dart';
import '../features/trips/trip_dashboard_screen.dart';
import '../features/trips/trip_list_screen.dart';
import 'app_lock_state.dart';
import 'sync_status_shell.dart';

/// Builds the app's [GoRouter], gating navigation on local (never network)
/// reads: whether a server has been configured ([ServerConfigStorage]),
/// whether a session is active ([AuthService.isAuthenticated]), and — if
/// biometrics are available on the device — whether the app has been
/// unlocked this run ([AppLockState.isUnlocked]). Re-evaluated automatically
/// whenever either changes (login/logout/token expiry/unlock), since both
/// are combined into `refreshListenable`.
GoRouter buildAppRouter({
  required AuthService authService,
  required ServerConfigStorage serverConfigStorage,
  required AppLockState appLockState,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/trips',
    refreshListenable: Listenable.merge([
      authService.isAuthenticated,
      appLockState.isUnlocked,
    ]),
    redirect: (context, state) async {
      final hasServer = await serverConfigStorage.read() != null;
      final location = state.matchedLocation;
      final onServerSetup = location == '/server-setup';
      final onLogin = location.startsWith('/login');
      final onLock = location == '/lock';

      if (!hasServer) {
        return onServerSetup ? null : '/server-setup';
      }
      if (!authService.isAuthenticated.value) {
        return onLogin ? null : '/login';
      }
      final needsUnlock =
          appLockState.biometricsAvailable && !appLockState.isUnlocked.value;
      if (needsUnlock) {
        return onLock ? null : '/lock';
      }
      if (onServerSetup || onLogin || onLock) {
        return '/trips';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/server-setup',
        builder: (context, state) => const ServerSetupScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/login/mfa',
        builder: (context, state) =>
            MfaScreen(mfaToken: state.extra! as String),
      ),
      GoRoute(
        path: '/lock',
        builder: (context, state) => const BiometricLockScreen(),
      ),
      GoRoute(
        path: '/reconnect',
        builder: (context, state) => const ReconnectScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            SyncStatusShell(authService: authService, child: child),
        routes: [
          GoRoute(
            path: '/trips',
            builder: (context, state) => const TripListScreen(),
          ),
          GoRoute(
            path: '/trips/:tripId',
            builder: (context, state) =>
                TripDashboardScreen(tripId: state.pathParameters['tripId']!),
          ),
        ],
      ),
    ],
  );
}
