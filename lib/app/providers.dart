import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/token_storage.dart';
import '../config/server_config.dart';
import '../config/server_config_resolver.dart';
import '../config/wifi_network_info.dart';
import '../network/api_client.dart';
import '../sync/outbox.dart';
import '../sync/pending_write.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_status.dart';
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

/// Durable storage for queued offline writes (see docs/offline-sync.md).
final outboxStoreProvider = Provider<OutboxStore>(
  (ref) => PreferencesOutboxStore(),
);

final outboxProvider = Provider<Outbox>((ref) {
  final outbox = Outbox(store: ref.watch(outboxStoreProvider));
  ref.onDispose(outbox.dispose);
  return outbox;
});

/// Every feature's [SyncHandler]s, keyed by the [PendingWrite.kind] they
/// push. A feature that queues writes adds its entries here.
final syncHandlersProvider = Provider<Map<String, SyncHandler>>(
  (ref) => const {},
);

/// Drains [outboxProvider]. Also drains whenever the user logs in, so
/// writes held back by a 401 go out as soon as a session exists again.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    outbox: ref.watch(outboxProvider),
    handlers: ref.watch(syncHandlersProvider),
  );
  final isAuthenticated = ref.watch(authServiceProvider).isAuthenticated;
  void onAuthChanged() {
    if (isAuthenticated.value) unawaited(engine.drain());
  }

  isAuthenticated.addListener(onAuthChanged);
  ref.onDispose(() {
    isAuthenticated.removeListener(onAuthChanged);
    unawaited(engine.dispose());
  });
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.status;
  yield* engine.statusChanges;
});
