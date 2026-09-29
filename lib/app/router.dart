import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../config/server_config.dart';
import '../deep_links/deep_link.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/mfa_screen.dart';
import '../features/server_setup/server_setup_screen.dart';
import '../features/trip_invites/join_trip_screen.dart';
import '../features/trip_invites/trip_invite_repository.dart';
import '../features/trips/trip_dashboard_screen.dart';
import '../features/trips/trip_list_screen.dart';

/// Builds the app's [GoRouter], gating navigation on two local (never
/// network) reads: whether a server has been configured
/// ([ServerConfigStorage]) and whether a session is active
/// ([AuthService.isAuthenticated]). Re-evaluated automatically whenever
/// [AuthService.isAuthenticated] changes (login/logout/token expiry), since
/// it's passed as `refreshListenable`.
///
/// Links handed over by the OS (`trek://join/<token>`, `trek://trips/<id>`)
/// are normalized to their in-app location via [DeepLink.parse]. A trip
/// invite link opened while signed out is remembered through
/// [tripInvites] and reopened right after login.
GoRouter buildAppRouter({
  required AuthService authService,
  required ServerConfigStorage serverConfigStorage,
  TripInviteRepository? tripInvites,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/trips',
    refreshListenable: authService.isAuthenticated,
    redirect: (context, state) async {
      if (state.uri.hasScheme) {
        return DeepLink.parse(state.uri)?.location ?? '/trips';
      }
      final hasServer = await serverConfigStorage.read() != null;
      final location = state.matchedLocation;
      final onServerSetup = location == '/server-setup';
      final onLogin = location.startsWith('/login');

      if (!hasServer) {
        return onServerSetup ? null : '/server-setup';
      }
      if (!authService.isAuthenticated.value) {
        if (onLogin) return null;
        final link = DeepLink.parse(state.uri);
        if (link is JoinTripLink) {
          await _bestEffort(() => tripInvites?.remember(link.token));
        }
        return '/login';
      }
      if (onServerSetup || onLogin) {
        final pending = await _bestEffort(tripInvites?.firstUnconfirmed);
        return pending == null
            ? '/trips'
            : JoinTripLink(pending.token).location;
      }
      return null;
    },
    // A link with no matching route (e.g. an unrecognized `trek://` path)
    // falls back to the trip list rather than an error page.
    onException: (context, state, router) => router.go('/trips'),
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
        path: '/trips',
        builder: (context, state) => const TripListScreen(),
      ),
      GoRoute(
        path: '/join/:token',
        builder: (context, state) =>
            JoinTripScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(
        path: '/trips/:tripId',
        builder: (context, state) =>
            TripDashboardScreen(tripId: state.pathParameters['tripId']!),
      ),
    ],
  );
}

/// Runs a local invite-store operation without letting a storage failure
/// block navigation — the invite is dropped, but the user still gets where
/// they were going.
Future<T?> _bestEffort<T>(Future<T?>? Function()? operation) async {
  try {
    return await operation?.call();
  } catch (error) {
    debugPrint('Router: trip invite store unavailable: $error');
    return null;
  }
}
