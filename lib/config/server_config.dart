import 'package:shared_preferences/shared_preferences.dart';

/// The Trek server instance(s) this app talks to.
///
/// Trek is self-hosted — there is no fixed vendor API URL. [publicUrl] is
/// always reachable (a domain behind a reverse proxy, dynamic DNS, etc.).
/// [privateUrl] is an optional local-network address (e.g.
/// `http://192.168.1.50:3000`) used only while the device is connected to
/// one of [trustedWifiNetworks] — the same "internal URL" pattern apps like
/// Home Assistant use to switch to a LAN address at home.
class ServerConfig {
  const ServerConfig({
    required this.publicUrl,
    this.privateUrl,
    this.trustedWifiNetworks = const {},
  });

  final String publicUrl;
  final String? privateUrl;

  /// Wi-Fi SSIDs on which [privateUrl] should be used instead of
  /// [publicUrl]. Empty means always use [publicUrl].
  final Set<String> trustedWifiNetworks;

  /// Picks [privateUrl] when [currentSsid] matches a trusted network and a
  /// private URL is configured; otherwise falls back to [publicUrl].
  String resolveBaseUrl(String? currentSsid) {
    final private = privateUrl;
    if (private != null &&
        currentSsid != null &&
        trustedWifiNetworks.contains(currentSsid)) {
      return private;
    }
    return publicUrl;
  }

  /// Validates and normalizes a user-entered server address (used for both
  /// [publicUrl] and [privateUrl]): requires an absolute `http`/`https` URL,
  /// strips a trailing slash. Throws [FormatException] otherwise.
  static String validateUrl(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    final isValid =
        uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!isValid) {
      throw const FormatException(
        'Enter a full server address, e.g. https://trek.example.com',
      );
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

/// Persists the configured [ServerConfig] between app launches.
abstract class ServerConfigStorage {
  Future<ServerConfig?> read();
  Future<void> write(ServerConfig config);
  Future<void> clear();
}

/// Stores the server config in plain local storage (`shared_preferences`) —
/// unlike the session token, none of it is a secret, so it doesn't need the
/// Keychain/Keystore-backed `SecureTokenStorage`.
class PreferencesServerConfigStorage implements ServerConfigStorage {
  PreferencesServerConfigStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _publicUrlKey = 'trek.server.public_url';
  static const _privateUrlKey = 'trek.server.private_url';
  static const _trustedWifiNetworksKey = 'trek.server.trusted_wifi_networks';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ServerConfig?> read() async {
    final publicUrl = await _preferences.getString(_publicUrlKey);
    if (publicUrl == null) return null;
    final privateUrl = await _preferences.getString(_privateUrlKey);
    final trustedWifiNetworks = await _preferences.getStringList(
      _trustedWifiNetworksKey,
    );
    return ServerConfig(
      publicUrl: publicUrl,
      privateUrl: privateUrl,
      trustedWifiNetworks: trustedWifiNetworks?.toSet() ?? const {},
    );
  }

  @override
  Future<void> write(ServerConfig config) async {
    await _preferences.setString(_publicUrlKey, config.publicUrl);
    final privateUrl = config.privateUrl;
    if (privateUrl != null) {
      await _preferences.setString(_privateUrlKey, privateUrl);
    } else {
      await _preferences.remove(_privateUrlKey);
    }
    await _preferences.setStringList(
      _trustedWifiNetworksKey,
      config.trustedWifiNetworks.toList(),
    );
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_publicUrlKey);
    await _preferences.remove(_privateUrlKey);
    await _preferences.remove(_trustedWifiNetworksKey);
  }
}
