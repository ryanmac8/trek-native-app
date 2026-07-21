import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/config/server_config.dart';

void main() {
  group('ServerConfig.validateUrl', () {
    test('accepts a plain https URL', () {
      expect(
        ServerConfig.validateUrl('https://trek.example.com'),
        'https://trek.example.com',
      );
    });

    test('accepts http for a self-hosted instance on the LAN', () {
      expect(
        ServerConfig.validateUrl('http://192.168.1.50:3000'),
        'http://192.168.1.50:3000',
      );
    });

    test('trims whitespace and a trailing slash', () {
      expect(
        ServerConfig.validateUrl('  https://trek.example.com/  '),
        'https://trek.example.com',
      );
    });

    test('rejects an empty string', () {
      expect(() => ServerConfig.validateUrl(''), throwsFormatException);
    });

    test('rejects a bare hostname with no scheme', () {
      expect(
        () => ServerConfig.validateUrl('trek.example.com'),
        throwsFormatException,
      );
    });

    test('rejects a non-http(s) scheme', () {
      expect(
        () => ServerConfig.validateUrl('ftp://trek.example.com'),
        throwsFormatException,
      );
    });
  });

  group('ServerConfig.resolveBaseUrl', () {
    test('uses the public URL when no private endpoints are configured', () {
      const config = ServerConfig(publicUrl: 'https://trek.example.com');

      expect(config.resolveBaseUrl('HomeWifi'), 'https://trek.example.com');
    });

    test('uses the public URL when not on any endpoint\'s network', () {
      const config = ServerConfig(
        publicUrl: 'https://trek.example.com',
        privateEndpoints: [
          PrivateEndpoint(
            url: 'http://192.168.1.50:3000',
            wifiNetwork: 'HomeWifi',
          ),
        ],
      );

      expect(
        config.resolveBaseUrl('CoffeeShopWifi'),
        'https://trek.example.com',
      );
      expect(config.resolveBaseUrl(null), 'https://trek.example.com');
    });

    test('uses the matching endpoint\'s URL when on its Wi-Fi network', () {
      const config = ServerConfig(
        publicUrl: 'https://trek.example.com',
        privateEndpoints: [
          PrivateEndpoint(
            url: 'http://192.168.1.50:3000',
            wifiNetwork: 'HomeWifi',
          ),
        ],
      );

      expect(config.resolveBaseUrl('HomeWifi'), 'http://192.168.1.50:3000');
    });

    test('picks the right endpoint among several by Wi-Fi network', () {
      const config = ServerConfig(
        publicUrl: 'https://trek.example.com',
        privateEndpoints: [
          PrivateEndpoint(url: 'http://192.168.1.50:3000', wifiNetwork: 'Home'),
          PrivateEndpoint(url: 'http://10.0.0.5:3000', wifiNetwork: 'Office'),
        ],
      );

      expect(config.resolveBaseUrl('Office'), 'http://10.0.0.5:3000');
      expect(config.resolveBaseUrl('Home'), 'http://192.168.1.50:3000');
    });
  });

  group('PreferencesServerConfigStorage', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesServerConfigStorage storage;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      storage = PreferencesServerConfigStorage();
    });

    test('read() returns null when nothing has been configured', () async {
      expect(await storage.read(), isNull);
    });

    test('write() then read() round-trips a public-only config', () async {
      await storage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );

      final result = await storage.read();

      expect(result?.publicUrl, 'https://trek.example.com');
      expect(result?.privateEndpoints, isEmpty);
    });

    test(
      'write() then read() round-trips public URL + several private endpoints',
      () async {
        await storage.write(
          const ServerConfig(
            publicUrl: 'https://trek.example.com',
            privateEndpoints: [
              PrivateEndpoint(
                url: 'http://192.168.1.50:3000',
                wifiNetwork: 'HomeWifi',
              ),
              PrivateEndpoint(
                url: 'http://10.0.0.5:3000',
                wifiNetwork: 'GarageWifi',
              ),
            ],
          ),
        );

        final result = await storage.read();

        expect(result?.publicUrl, 'https://trek.example.com');
        expect(result?.privateEndpoints, [
          const PrivateEndpoint(
            url: 'http://192.168.1.50:3000',
            wifiNetwork: 'HomeWifi',
          ),
          const PrivateEndpoint(
            url: 'http://10.0.0.5:3000',
            wifiNetwork: 'GarageWifi',
          ),
        ]);
      },
    );

    test(
      'write() without private endpoints clears any previously stored ones',
      () async {
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

        await storage.write(
          const ServerConfig(publicUrl: 'https://trek.example.com'),
        );

        final result = await storage.read();
        expect(result?.privateEndpoints, isEmpty);
      },
    );

    test('clear() removes the configured server', () async {
      await storage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );

      await storage.clear();

      expect(await storage.read(), isNull);
    });
  });
}
