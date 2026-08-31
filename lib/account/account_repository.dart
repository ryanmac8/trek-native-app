import 'account_api.dart';
import 'account_local_store.dart';
import 'account_models.dart';

/// Offline-first front door for the signed-in account (see
/// docs/offline-first.md). The settings screen uses this, not [AccountApi]
/// directly.
///
/// - [cachedAccount] never touches the network, so the screen can paint the
///   last-known profile instantly.
/// - [refreshAccount] fetches the current account, writes it to the cache,
///   and returns it. A `NetworkException` propagates: the screen keeps
///   showing whatever [cachedAccount] returned, marked as stale, or shows
///   an explicit offline state if it has nothing cached.
/// - [clearCachedAccount] drops the cached profile — call it on an explicit
///   sign-out so the next account can't briefly see the previous one.
///
/// An `UnauthorizedException` from [refreshAccount] also propagates: the
/// shared client has already cleared the session, and the router redirects
/// to login.
class AccountRepository {
  AccountRepository({
    required AccountApi accountApi,
    required AccountLocalStore localStore,
  }) : _api = accountApi,
       _localStore = localStore;

  final AccountApi _api;
  final AccountLocalStore _localStore;

  Future<TrekAccount?> cachedAccount() => _localStore.read();

  Future<TrekAccount> refreshAccount() async {
    final account = await _api.fetchAccount();
    await _localStore.write(account);
    return account;
  }

  Future<void> clearCachedAccount() => _localStore.clear();
}
