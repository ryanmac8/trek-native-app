import 'server_config.dart';
import 'wifi_network_info.dart';

/// Resolves the effective server base URL for `ApiClient`'s `getBaseUrl`,
/// consulting the current Wi-Fi network on every call — so switching
/// networks (e.g. leaving home) takes effect on the next request without
/// restarting the app.
class ServerConfigResolver {
  ServerConfigResolver({
    required ServerConfigStorage storage,
    required WifiNetworkInfo wifiInfo,
  }) : _storage = storage,
       _wifiInfo = wifiInfo;

  final ServerConfigStorage _storage;
  final WifiNetworkInfo _wifiInfo;

  /// Throws [StateError] if no server has been configured yet — callers
  /// should only construct an `ApiClient` with this after server setup
  /// (`ServerConfigStorage` has a value).
  Future<String> resolveBaseUrl() async {
    final config = await _storage.read();
    if (config == null) {
      throw StateError('No server configured yet.');
    }
    final ssid = await _wifiInfo.currentSsid();
    return config.resolveBaseUrl(ssid);
  }
}
