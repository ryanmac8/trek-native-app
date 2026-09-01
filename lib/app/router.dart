import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../config/server_config.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/mfa_screen.dart';
import '../features/server_setup/server_setup_screen.dart';
import '../features/transit/transit_search_screen.dart';
import '../features/trips/trip_dashboard_screen.dart';
import '../features/trips/trip_list_screen.dart';

/// Builds the app's [GoRouter], gating navigation on:
/// 1. Server configuration ([ServerConfig]) - no server → show setup
/// 2. Auth state ([AuthService.isAuthenticated]) - not logged in → show login
/// Re-evaluated automatically as auth state changes.
GoRouter buildAppRouter({
  required AuthService authService,
  required ServerConfig serverConfig,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/trips',
    redirect: (context, state) async {
      final hasServer = serverConfig != null;
      final location = state.matchedLocation;
      final onServerSetup = location == '/server-setup';
      final onLogin = location.startsWith('/login');

      if (!hasServer) {
        return onServerSetup ? null : '/server-setup';
      }
      if (!authService.isAuthenticated.value) {
        return onLogin ? null : '/login';
      }
      if (onServerSetup || onLogin) {
        return '/trips';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/server-setup',
        builder: (context, state) => const ServerSetupScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/login/mfa',
        builder: (context, state) => const MfaScreen(mfaToken: state.extra['mfaToken'] as String),
      ),
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TripListScreen(),
      ),
      GoRoute(
        path: '/transit',
        builder: (context, state) => const TransitSearchScreen(),
      ),
      GoRoute(
        path: '/trips/:tripId',
        builder: (context, state) =>
            TripDashboardScreen(tripId: state.pathParameters['tripId']!),
      ),
    ],
  );
}
