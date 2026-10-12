import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
import '../features/share_import/share_import_api.dart';
import '../features/share_import/share_import_repository.dart';
import '../features/share_import/share_import_store.dart';
import '../network/api_client.dart';
import '../share_intake/share_intake.dart';
import '../share_intake/shared_map_link.dart';
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
    incomingShare: ref.watch(incomingShareProvider),
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

/// Text shared into Trek from other apps' share sheets — see
/// docs/share-import.md.
final shareIntakeProvider = Provider<ShareIntake>(
  (ref) => MethodChannelShareIntake(),
);

/// The map link currently being shared into a trip, or `null`. The router
/// shows `/share-import` while this is set; clearing it dismisses the
/// screen.
final incomingShareProvider = Provider<ValueNotifier<SharedMapLink?>>((ref) {
  final notifier = ValueNotifier<SharedMapLink?>(null);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final shareImportApiProvider = Provider<ShareImportApi>(
  (ref) => ShareImportApi(apiClient: ref.watch(apiClientProvider)),
);

/// Cached trip list for the picker and the queue of imports not yet sent.
final shareImportStoreProvider = Provider<ShareImportStore>(
  (ref) => PreferencesShareImportStore(),
);

/// A single app-wide instance, so the share screen and the background
/// flush share one queue lock.
final shareImportRepositoryProvider = Provider<ShareImportRepository>((ref) {
  final serverConfigStorage = ref.watch(serverConfigStorageProvider);
  return ShareImportRepository(
    api: ref.watch(shareImportApiProvider),
    store: ref.watch(shareImportStoreProvider),
    currentServer: () async => (await serverConfigStorage.read())?.publicUrl,
  );
});
