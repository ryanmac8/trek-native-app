import 'package:flutter_test/flutter_test.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/config/server_config_resolver.dart';
import 'package:trek/config/wifi_network_info.dart';

class _InMemoryServerConfigStorage implements ServerConfigStorage {
  ServerConfig? _config;

  @override
  Future<ServerConfig?> read() async => _config;

  @override
  Future<void> write(ServerConfig config) async => _config = config;

  @override
  Future<void> clear() async => _config = null;
}

class _FakeWifiNetworkInfo implements WifiNetworkInfo {
  _FakeWifiNetworkInfo(this.ssid);

  String? ssid;

  @override
  Future<String?> currentSsid() async => ssid;
}

void main() {
  group('ServerConfigResolver', () {
    test('throws StateError when no server has been configured', () async {
      final resolver = ServerConfigResolver(
        storage: _InMemoryServerConfigStorage(),
        wifiInfo: _FakeWifiNetworkInfo(null),
      );

      expect(resolver.resolveBaseUrl(), throwsStateError);
    });

    test('resolves the public URL when off any endpoint\'s network', () async {
      final storage = _InMemoryServerConfigStorage();
      await storage.write(
        const ServerConfig(
          publicUrl: 'https://trek.example.com',
          privateEndpoints: [
            PrivateEndpoint(
              url: 'http://192.168.1.50:3000',
              wifiNetwork: 'HomeWifi',
            ),
          ],
        ),
      );
      final resolver = ServerConfigResolver(
        storage: storage,
        wifiInfo: _FakeWifiNetworkInfo('CoffeeShopWifi'),
      );

      expect(await resolver.resolveBaseUrl(), 'https://trek.example.com');
    });

    test(
      'resolves the matching endpoint\'s URL on its Wi-Fi network',
      () async {
        final storage = _InMemoryServerConfigStorage();
        await storage.write(
          const ServerConfig(
            publicUrl: 'https://trek.example.com',
            privateEndpoints: [
              PrivateEndpoint(
                url: 'http://192.168.1.50:3000',
                wifiNetwork: 'HomeWifi',
              ),
            ],
          ),
        );
        final wifiInfo = _FakeWifiNetworkInfo('HomeWifi');
        final resolver = ServerConfigResolver(
          storage: storage,
          wifiInfo: wifiInfo,
        );

        expect(await resolver.resolveBaseUrl(), 'http://192.168.1.50:3000');

        // Leaving the trusted network switches the next resolution back to
        // public without recreating the resolver or restarting the app.
        wifiInfo.ssid = 'CoffeeShopWifi';
        expect(await resolver.resolveBaseUrl(), 'https://trek.example.com');
      },
    );
  });
}
