import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
import '../network/api_client.dart';
import '../notifications/notifications_api.dart';
import '../notifications/notifications_local_store.dart';
import '../notifications/notifications_repository.dart';
import '../transit/transit_api.dart';
import '../transit/transit_local_store.dart';
import '../transit/transit_repository.dart';
import '../weather/weather_api.dart';
import '../weather/weather_local_store.dart';
import '../weather/weather_repository.dart';
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

/// Authenticated client for the rest of Trek's API — attaches a bearer token
/// via [AuthService.currentAccessToken] (a purely local read — see its doc
/// comment) and clears the local session on a 401 via
/// [AuthService.handleUnauthorized]. There's no refresh flow to retry
/// against. Added here for the notifications inbox, transit search, and
/// weather, the first places to need an authenticated client.
final apiClientProvider = Provider<ApiClient>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiClient(
    getBaseUrl: ref.watch(serverConfigResolverProvider).resolveBaseUrl,
    getAccessToken: () => authService.currentAccessToken,
    onUnauthorized: authService.handleUnauthorized,
  );
});

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  return NotificationsApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache + pending-reads outbox for the notifications
/// inbox — see docs/offline-first.md. A minimal, scoped-to-notifications
/// stand-in for the full local-persistence mechanism issue #21 will decide
/// on for the whole data model.
final notificationsLocalStoreProvider = Provider<NotificationsLocalStore>(
  (ref) => PreferencesNotificationsLocalStore(),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(
    notificationsApi: ref.watch(notificationsApiProvider),
    localStore: ref.watch(notificationsLocalStoreProvider),
  );
});

final transitApiProvider = Provider<TransitApi>((ref) {
  return TransitApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache for transit + airport search results — see
/// docs/offline-first.md. A minimal, feature-scoped stand-in for the full
/// local-persistence mechanism issue #21 will decide on.
final transitLocalStoreProvider = Provider<TransitLocalStore>(
  (ref) => PreferencesTransitLocalStore(),
);

final transitRepositoryProvider = Provider<TransitRepository>((ref) {
  return TransitRepository(
    transitApi: ref.watch(transitApiProvider),
    localStore: ref.watch(transitLocalStoreProvider),
  );
});

final weatherApiProvider = Provider<WeatherApi>((ref) {
  return WeatherApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache for weather lookups — see docs/offline-first.md.
/// A minimal, feature-scoped stand-in for the full local-persistence
/// mechanism issue #21 will decide on.
final weatherLocalStoreProvider = Provider<WeatherLocalStore>(
  (ref) => PreferencesWeatherLocalStore(),
);

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(
    weatherApi: ref.watch(weatherApiProvider),
    localStore: ref.watch(weatherLocalStoreProvider),
  );
});
