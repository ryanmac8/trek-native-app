import 'package:shared_preferences/shared_preferences.dart';

/// The Trek server instance this app talks to.
///
/// Trek is self-hosted ("Your trips. Your plan. Your server.") — there is no
/// fixed vendor-run API like `api.trek.app`. Each user points the app at
/// their own running instance, the same way Nextcloud or Immich clients
/// work, so this is a single user-entered URL rather than a set of fixed
/// dev/staging/prod constants.
class ServerConfig {
  const ServerConfig({required this.baseUrl});

  final String baseUrl;

  /// Parses and normalizes user input (e.g. from a "server address" field)
  /// into a [ServerConfig]. Requires an absolute `http`/`https` URL and
  /// strips any trailing slash so it composes cleanly with [ApiClient]'s
  /// paths (which always start with `/`).
  factory ServerConfig.parse(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    final isValid =
        uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!isValid) {
      throw const FormatException(
        'Enter your Trek server\'s full address, e.g. https://trek.example.com',
      );
    }
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return ServerConfig(baseUrl: normalized);
  }
}

/// Persists the configured [ServerConfig] between app launches.
abstract class ServerConfigStorage {
  Future<ServerConfig?> read();
  Future<void> write(ServerConfig config);
  Future<void> clear();
}

/// Stores the server URL in plain local storage (`shared_preferences`) —
/// unlike the session token, it isn't a secret, so it doesn't need the
/// Keychain/Keystore-backed `SecureTokenStorage`.
class PreferencesServerConfigStorage implements ServerConfigStorage {
  PreferencesServerConfigStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _baseUrlKey = 'trek.server.base_url';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ServerConfig?> read() async {
    final baseUrl = await _preferences.getString(_baseUrlKey);
    if (baseUrl == null) return null;
    return ServerConfig(baseUrl: baseUrl);
  }

  @override
  Future<void> write(ServerConfig config) {
    return _preferences.setString(_baseUrlKey, config.baseUrl);
  }

  @override
  Future<void> clear() {
    return _preferences.remove(_baseUrlKey);
  }
}
