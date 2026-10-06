import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/local_data.dart';
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

/// Every feature store holding account data registers itself here (from the
/// provider that creates it) so logout and account switches clear it.
final localDataRegistryProvider = Provider<LocalDataRegistry>(
  (ref) => LocalDataRegistry(),
);

final localDataOwnerStorageProvider = Provider<LocalDataOwnerStorage>(
  (ref) => PreferencesLocalDataOwnerStorage(),
);

final authServiceProvider = Provider<AuthService>((ref) {
  final serverConfigStorage = ref.watch(serverConfigStorageProvider);
  return AuthService(
    apiClient: ref.watch(authApiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    localData: ref.watch(localDataRegistryProvider),
    ownerStorage: ref.watch(localDataOwnerStorageProvider),
    getServerUrl: () async => (await serverConfigStorage.read())?.publicUrl,
  );
});

final appRouterProvider = Provider<GoRouter>((ref) {
  return buildAppRouter(
    authService: ref.watch(authServiceProvider),
    serverConfigStorage: ref.watch(serverConfigStorageProvider),
  );
});
