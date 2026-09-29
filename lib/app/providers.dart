import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
import '../features/trip_invites/pending_invite_store.dart';
import '../features/trip_invites/trip_invite_api.dart';
import '../features/trip_invites/trip_invite_repository.dart';
import '../network/api_client.dart';
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

final serverConfigResolverProvider = Provider<ServerConfigResolver>((ref) {
  return ServerConfigResolver(
    storage: ref.watch(serverConfigStorageProvider),
    wifiInfo: ref.watch(wifiNetworkInfoProvider),
  );
});

/// Unauthenticated client for the `/api/auth/*` endpoints — [AuthService]
/// wraps this. The authenticated client for the rest of the API is
/// [apiClientProvider] below.
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

final appRouterProvider = Provider<GoRouter>((ref) {
  return buildAppRouter(
    authService: ref.watch(authServiceProvider),
    serverConfigStorage: ref.watch(serverConfigStorageProvider),
    tripInvites: ref.watch(tripInviteRepositoryProvider),
  );
});

/// Authenticated client for the rest of Trek's API — attaches a bearer
/// token via [AuthService.currentAccessToken] (a purely local read) and
/// clears the local session on a 401 via [AuthService.handleUnauthorized].
/// There's no refresh flow to retry against.
final apiClientProvider = Provider<ApiClient>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiClient(
    getBaseUrl: ref.watch(serverConfigResolverProvider).resolveBaseUrl,
    getAccessToken: () => authService.currentAccessToken,
    onUnauthorized: authService.handleUnauthorized,
  );
});

final tripInviteApiProvider = Provider<TripInviteApi>(
  (ref) => TripInviteApi(apiClient: ref.watch(apiClientProvider)),
);

/// Durable local list of trip invites opened while signed out or confirmed
/// while offline — see docs/deep-links.md.
final pendingInviteStoreProvider = Provider<PendingInviteStore>(
  (ref) => PreferencesPendingInviteStore(),
);

/// A single app-wide instance, so the router, the join screen, and the
/// trip list share one store lock.
final tripInviteRepositoryProvider = Provider<TripInviteRepository>((ref) {
  final serverConfigStorage = ref.watch(serverConfigStorageProvider);
  return TripInviteRepository(
    api: ref.watch(tripInviteApiProvider),
    store: ref.watch(pendingInviteStoreProvider),
    currentServer: () async => (await serverConfigStorage.read())?.publicUrl,
  );
});
