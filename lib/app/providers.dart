import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../addons/addon_flags_controller.dart';
import '../addons/addon_flags_local_store.dart';
import '../addons/addon_flags_repository.dart';
import '../addons/addons_api.dart';
import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
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

final addonsApiProvider = Provider<AddonsApi>((ref) {
  return AddonsApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache of the instance's add-on flags — see
/// docs/feature-flags.md.
final addonFlagsLocalStoreProvider = Provider<AddonFlagsLocalStore>(
  (ref) => PreferencesAddonFlagsLocalStore(),
);

/// The server a cached set of add-on flags belongs to: the configured
/// public server URL, or `null` before server setup. A local read. Flags
/// are instance-wide, so — unlike per-account caches — no user id.
final addonFlagsCacheScopeProvider = Provider<Future<String?> Function()>((
  ref,
) {
  final serverConfigStorage = ref.watch(serverConfigStorageProvider);
  return () async => (await serverConfigStorage.read())?.publicUrl;
});

final addonFlagsRepositoryProvider = Provider<AddonFlagsRepository>((ref) {
  return AddonFlagsRepository(
    addonsApi: ref.watch(addonsApiProvider),
    localStore: ref.watch(addonFlagsLocalStoreProvider),
    cacheScope: ref.watch(addonFlagsCacheScopeProvider),
  );
});

/// The instance's add-on flags for the UI (cached first, refreshed in the
/// background). Gate add-on-backed screens and tabs on
/// `ref.watch(addonFlagsProvider).isEnabled(AddonIds.x)`.
final addonFlagsProvider =
    NotifierProvider<AddonFlagsController, AddonFlagsState>(
      () => AddonFlagsController(
        (ref) => ref.watch(addonFlagsRepositoryProvider),
      ),
    );
