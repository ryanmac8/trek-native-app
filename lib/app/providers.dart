import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
import '../home_widgets/home_widget_publisher.dart';
import '../home_widgets/next_trip_widget_sync.dart';
import '../home_widgets/widget_trip_api.dart';
import '../home_widgets/widget_trip_store.dart';
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

final widgetTripApiProvider = Provider<WidgetTripApi>((ref) {
  return WidgetTripApi(apiClient: ref.watch(apiClientProvider));
});

/// Local (non-secure) cache of the trip list behind the home-screen
/// widget — see docs/offline-first.md and docs/home-widgets.md.
final widgetTripStoreProvider = Provider<WidgetTripStore>(
  (ref) => PreferencesWidgetTripStore(),
);

final homeWidgetPublisherProvider = Provider<HomeWidgetPublisher>(
  (ref) => PluginHomeWidgetPublisher(),
);

/// The account the cached widget trip list belongs to: the configured
/// public server URL plus the signed-in user id, or `null` without a
/// session. Both are local reads.
final homeWidgetCacheScopeProvider = Provider<Future<String?> Function()>((
  ref,
) {
  final authService = ref.watch(authServiceProvider);
  final serverConfigStorage = ref.watch(serverConfigStorageProvider);
  return () async {
    final userId = await authService.currentUserId;
    final server = await serverConfigStorage.read();
    if (userId == null || server == null) return null;
    return '${server.publicUrl}#$userId';
  };
});

/// A single app-wide instance, so overlapping refreshes (startup, sign-in,
/// app resume) share one in-flight request.
final nextTripWidgetSyncProvider = Provider<NextTripWidgetSync>((ref) {
  return NextTripWidgetSync(
    api: ref.watch(widgetTripApiProvider),
    store: ref.watch(widgetTripStoreProvider),
    publisher: ref.watch(homeWidgetPublisherProvider),
    cacheScope: ref.watch(homeWidgetCacheScopeProvider),
  );
});
