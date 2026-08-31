import '../network/api_client.dart';
import 'account_models.dart';

/// Wraps Trek's current-account endpoint. It is JWT-guarded
/// (`AuthController`), so this uses the authenticated [ApiClient]
/// (`apiClientProvider`).
///
/// This is a thin transport layer: it does no caching and no offline
/// handling — [AccountRepository] is the offline-first front door screens
/// use. See docs/settings.md.
class AccountApi {
  AccountApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/auth/me` → the signed-in user. A dead session surfaces as
  /// [UnauthorizedException] (the shared client clears the local session
  /// first); the caller lets the router redirect to login.
  Future<TrekAccount> fetchAccount() async {
    final response =
        await _apiClient.get('/api/auth/me') as Map<String, dynamic>;
    final user = response['user'] as Map<String, dynamic>? ?? const {};
    return TrekAccount.fromJson(user);
  }
}
