import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A local-network address for the Trek server, used only while the device
/// is connected to [wifiNetwork] — the same "internal URL" pattern apps like
/// Home Assistant use to switch to a LAN address at home. Unlike the old
/// single-private-URL model, each endpoint is tied to exactly one Wi-Fi
/// network, so e.g. home and office LAN addresses can coexist.
class PrivateEndpoint {
  const PrivateEndpoint({required this.url, required this.wifiNetwork});

  final String url;
  final String wifiNetwork;

  Map<String, String> toJson() => {'url': url, 'wifiNetwork': wifiNetwork};

  factory PrivateEndpoint.fromJson(Map<String, dynamic> json) =>
      PrivateEndpoint(
        url: json['url'] as String,
        wifiNetwork: json['wifiNetwork'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PrivateEndpoint &&
      other.url == url &&
      other.wifiNetwork == wifiNetwork;

  @override
  int get hashCode => Object.hash(url, wifiNetwork);
}

/// The Trek server instance(s) this app talks to.
///
/// Trek is self-hosted — there is no fixed vendor API URL. [publicUrl] is
/// always reachable (a domain behind a reverse proxy, dynamic DNS, etc.).
/// [privateEndpoints] are optional local-network addresses, each active only
/// while the device is connected to its own associated Wi-Fi network.
class ServerConfig {
  const ServerConfig({
    required this.publicUrl,
    this.privateEndpoints = const [],
  });

  final String publicUrl;
  final List<PrivateEndpoint> privateEndpoints;

  /// Picks the private endpoint whose Wi-Fi network matches [currentSsid];
  /// otherwise falls back to [publicUrl].
  String resolveBaseUrl(String? currentSsid) {
    if (currentSsid == null) return publicUrl;
    for (final endpoint in privateEndpoints) {
      if (endpoint.wifiNetwork == currentSsid) return endpoint.url;
    }
    return publicUrl;
  }

  /// Validates and normalizes a user-entered server address (used for
  /// [publicUrl] and every [PrivateEndpoint.url]): requires an absolute
  /// `http`/`https` URL, strips a trailing slash. Throws [FormatException]
  /// otherwise.
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
  static const _privateEndpointsKey = 'trek.server.private_endpoints';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ServerConfig?> read() async {
    final publicUrl = await _preferences.getString(_publicUrlKey);
    if (publicUrl == null) return null;
    final encodedEndpoints = await _preferences.getStringList(
      _privateEndpointsKey,
    );
    return ServerConfig(
      publicUrl: publicUrl,
      privateEndpoints:
          encodedEndpoints
              ?.map(
                (encoded) => PrivateEndpoint.fromJson(
                  jsonDecode(encoded) as Map<String, dynamic>,
                ),
              )
              .toList() ??
          const [],
    );
  }

  @override
  Future<void> write(ServerConfig config) async {
    await _preferences.setString(_publicUrlKey, config.publicUrl);
    await _preferences.setStringList(
      _privateEndpointsKey,
      config.privateEndpoints
          .map((endpoint) => jsonEncode(endpoint.toJson()))
          .toList(),
    );
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_publicUrlKey);
    await _preferences.remove(_privateEndpointsKey);
  }
}
