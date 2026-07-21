import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/config/server_config.dart';

void main() {
  group('ServerConfig.parse', () {
    test('accepts a plain https URL', () {
      expect(
        ServerConfig.parse('https://trek.example.com').baseUrl,
        'https://trek.example.com',
      );
    });

    test('accepts http for a self-hosted instance on the LAN', () {
      expect(
        ServerConfig.parse('http://192.168.1.50:3000').baseUrl,
        'http://192.168.1.50:3000',
      );
    });

    test('trims whitespace and a trailing slash', () {
      expect(
        ServerConfig.parse('  https://trek.example.com/  ').baseUrl,
        'https://trek.example.com',
      );
    });

    test('rejects an empty string', () {
      expect(() => ServerConfig.parse(''), throwsFormatException);
    });

    test('rejects a bare hostname with no scheme', () {
      expect(
        () => ServerConfig.parse('trek.example.com'),
        throwsFormatException,
      );
    });

    test('rejects a non-http(s) scheme', () {
      expect(
        () => ServerConfig.parse('ftp://trek.example.com'),
        throwsFormatException,
      );
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

    test('write() then read() round-trips the server URL', () async {
      await storage.write(
        const ServerConfig(baseUrl: 'https://trek.example.com'),
      );

      final result = await storage.read();

      expect(result?.baseUrl, 'https://trek.example.com');
    });

    test('clear() removes the configured server URL', () async {
      await storage.write(
        const ServerConfig(baseUrl: 'https://trek.example.com'),
      );

      await storage.clear();

      expect(await storage.read(), isNull);
    });
  });
}
