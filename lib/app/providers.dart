import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
import '../network/api_client.dart';
import '../reservations/reservations_api.dart';
import '../reservations/reservations_local_store.dart';
import '../reservations/reservations_repository.dart';
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
/// wraps this. The authenticated client the rest of the API needs is
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

/// Authenticated client for the rest of the API — attaches a bearer token
/// via [AuthService.currentAccessToken] (a purely local read — see its doc
/// comment) and clears the local session on a 401 via
/// [AuthService.handleUnauthorized]. There's no refresh flow to retry
/// against; a non-blocking "reconnect" UX for the cleared-session case is a
/// follow-up, not this feature's job. This is the app's first authenticated
/// client, added for the Bookings tab.
final apiClientProvider = Provider<ApiClient>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiClient(
    getBaseUrl: ref.watch(serverConfigResolverProvider).resolveBaseUrl,
    getAccessToken: () => authService.currentAccessToken,
    onUnauthorized: authService.handleUnauthorized,
  );
});

final reservationsApiProvider = Provider<ReservationsApi>((ref) {
  return ReservationsApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache of each trip's reservations — see
/// docs/offline-first.md. A minimal, scoped-to-reservations stand-in for
/// the full local-persistence mechanism issue #21 will decide on for the
/// whole data model.
final reservationsLocalStoreProvider = Provider<ReservationsLocalStore>(
  (ref) => PreferencesReservationsLocalStore(),
);

final reservationsRepositoryProvider = Provider<ReservationsRepository>((ref) {
  return ReservationsRepository(
    reservationsApi: ref.watch(reservationsApiProvider),
    localStore: ref.watch(reservationsLocalStoreProvider),
  );
});
