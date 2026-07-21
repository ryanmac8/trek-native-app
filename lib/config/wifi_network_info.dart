import 'package:network_info_plus/network_info_plus.dart';

/// Looks up the SSID of the Wi-Fi network the device is currently connected
/// to, so [ServerConfig] can decide whether to use the private or public
/// server URL.
abstract class WifiNetworkInfo {
  /// The current Wi-Fi SSID, or `null` if the device isn't on Wi-Fi, or the
  /// SSID can't be read (permission not granted, iOS simulator, no "Access
  /// WiFi Information" entitlement, etc.). Callers must treat `null` as
  /// "fall back to the public URL," not as an error.
  Future<String?> currentSsid();
}

/// Real device implementation, backed by `network_info_plus`.
class DeviceWifiNetworkInfo implements WifiNetworkInfo {
  DeviceWifiNetworkInfo({NetworkInfo? networkInfo})
    : _networkInfo = networkInfo ?? NetworkInfo();

  final NetworkInfo _networkInfo;

  @override
  Future<String?> currentSsid() async {
    try {
      final ssid = await _networkInfo.getWifiName();
      // Android (and some iOS versions) wrap the SSID in quotes.
      return ssid?.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }
}
