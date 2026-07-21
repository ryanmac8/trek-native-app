import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/biometric_auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/server_health_check.dart';
import '../config/wifi_network_info.dart';
import '../network/api_client.dart';
import '../trips/trips_api.dart';
import '../trips/trips_local_store.dart';
import '../trips/trips_repository.dart';
import 'app_lock_state.dart';
import 'router.dart';

/// Where the self-hosted server URL is persisted (see
/// [PreferencesServerConfigStorage]). Read directly by the router's
/// redirect logic to decide whether server setup is needed.
final serverConfigStorageProvider = Provider<ServerConfigStorage>(
  (ref) => PreferencesServerConfigStorage(),
);

final wifiNetworkInfoProvider = Provider<WifiNetworkInfo>(
  (ref) => DeviceWifiNetworkInfo(),
);

/// Pings a candidate private endpoint's `/api/health` before it's saved —
/// see `NetworkingSettingsScreen`'s add-endpoint dialog.
final serverHealthCheckProvider = Provider<ServerHealthCheck>(
  (ref) => ServerHealthCheck(),
);

final serverConfigResolverProvider = Provider<ServerConfigResolver>((ref) {
  return ServerConfigResolver(
    storage: ref.watch(serverConfigStorageProvider),
    wifiInfo: ref.watch(wifiNetworkInfoProvider),
  );
});

/// Unauthenticated client for the `/api/auth/*` endpoints — [AuthService]
/// wraps this.
final authApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    getBaseUrl: ref.watch(serverConfigResolverProvider).resolveBaseUrl,
  );
});

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    apiClient: ref.watch(authApiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  );
});

/// Authenticated client for the rest of the API — attaches a bearer token
/// via [AuthService.currentAccessToken] and routes 401s to
/// [AuthService.handleUnauthorized], which flags [AuthService.needsReconnect]
/// rather than clearing the session (see docs/app-shell.md's "Auth
/// resilience" section for why).
final apiClientProvider = Provider<ApiClient>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiClient(
    getBaseUrl: ref.watch(serverConfigResolverProvider).resolveBaseUrl,
    getAccessToken: () => authService.currentAccessToken,
    onUnauthorized: authService.handleUnauthorized,
  );
});

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
  (ref) => DeviceBiometricAuthService(),
);

final tripsApiProvider = Provider<TripsApi>((ref) {
  return TripsApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache of the trip list — see docs/offline-first.md.
/// A minimal, scoped-to-trips stand-in for the full local-persistence
/// mechanism issue #21 will decide on for the whole data model.
final tripsLocalStoreProvider = Provider<TripsLocalStore>(
  (ref) => PreferencesTripsLocalStore(),
);

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(
    tripsApi: ref.watch(tripsApiProvider),
    localStore: ref.watch(tripsLocalStoreProvider),
  );
});

/// Single long-lived instance for the app run — see [AppLockState].
final appLockStateProvider = Provider<AppLockState>((ref) => AppLockState());

final appRouterProvider = Provider<GoRouter>((ref) {
  return buildAppRouter(
    authService: ref.watch(authServiceProvider),
    serverConfigStorage: ref.watch(serverConfigStorageProvider),
    appLockState: ref.watch(appLockStateProvider),
  );
});
