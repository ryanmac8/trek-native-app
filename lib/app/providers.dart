import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../collab/collab_api.dart';
import '../collab/collab_local_store.dart';
import '../collab/collab_repository.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
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
/// wraps this. A separate authenticated client (with a bearer token and
/// 401 handling wired to [AuthService.handleUnauthorized]) belongs to
/// whichever feature is the first to need it.
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
  );
});

/// Authenticated client for the rest of the API — attaches a bearer token
/// via [AuthService.currentAccessToken]. A 401 clears the local session via
/// [AuthService.handleUnauthorized] (there's no refresh flow to retry
/// against — see its doc comment); a non-blocking "reconnect" UX for that
/// case is a follow-up, not this feature's job. Added for Collab notes —
/// the first feature (besides auth) to need one.
final apiClientProvider = Provider<ApiClient>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiClient(
    getBaseUrl: ref.watch(serverConfigResolverProvider).resolveBaseUrl,
    getAccessToken: () => authService.currentAccessToken,
    onUnauthorized: authService.handleUnauthorized,
  );
});

final collabApiProvider = Provider<CollabApi>((ref) {
  return CollabApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache of each trip's collab notes — see
/// docs/offline-first.md. A minimal, scoped-to-notes stand-in for the full
/// local-persistence mechanism issue #21 will decide on for the whole data
/// model, the same shape as `PreferencesTodoLocalStore`.
final collabLocalStoreProvider = Provider<CollabLocalStore>(
  (ref) => PreferencesCollabLocalStore(),
);

final collabRepositoryProvider = Provider<CollabRepository>((ref) {
  return CollabRepository(
    collabApi: ref.watch(collabApiProvider),
    localStore: ref.watch(collabLocalStoreProvider),
  );
});
