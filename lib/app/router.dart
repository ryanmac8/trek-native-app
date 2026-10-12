import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../config/server_config.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/mfa_screen.dart';
import '../features/server_setup/server_setup_screen.dart';
import '../features/share_import/share_import_screen.dart';
import '../features/trips/trip_dashboard_screen.dart';
import '../features/trips/trip_list_screen.dart';
import '../share_intake/shared_map_link.dart';

/// Builds the app's [GoRouter], gating navigation on two local (never
/// network) reads: whether a server has been configured
/// ([ServerConfigStorage]) and whether a session is active
/// ([AuthService.isAuthenticated]). Re-evaluated automatically whenever
/// [AuthService.isAuthenticated] changes (login/logout/token expiry), since
/// it's passed as `refreshListenable`.
///
/// While [incomingShare] holds a map link shared from another app, a
/// signed-in user is kept on `/share-import`; a signed-out one goes through
/// login first and lands there afterwards. Clearing it returns to `/trips`.
GoRouter buildAppRouter({
  required AuthService authService,
  required ServerConfigStorage serverConfigStorage,
  ValueListenable<SharedMapLink?>? incomingShare,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/trips',
    refreshListenable: Listenable.merge([
      authService.isAuthenticated,
      ?incomingShare,
    ]),
    redirect: (context, state) async {
      final hasServer = await serverConfigStorage.read() != null;
      final location = state.matchedLocation;
      final onServerSetup = location == '/server-setup';
      final onLogin = location.startsWith('/login');

      if (!hasServer) {
        return onServerSetup ? null : '/server-setup';
      }
      if (!authService.isAuthenticated.value) {
        return onLogin ? null : '/login';
      }
      final onShareImport = location == '/share-import';
      if (incomingShare?.value != null) {
        return onShareImport ? null : '/share-import';
      }
      if (onServerSetup || onLogin || onShareImport) {
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
        path: '/share-import',
        builder: (context, state) => const ShareImportScreen(),
      ),
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
  );
}
