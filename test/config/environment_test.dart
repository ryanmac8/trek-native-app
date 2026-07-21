import 'package:flutter_test/flutter_test.dart';
import 'package:trek/config/environment.dart';

void main() {
  group('EnvironmentConfig', () {
    test('forEnvironment resolves the correct base URL per environment', () {
      expect(
        EnvironmentConfig.forEnvironment(Environment.dev).apiBaseUrl,
        'https://dev-api.trek.app',
      );
      expect(
        EnvironmentConfig.forEnvironment(Environment.staging).apiBaseUrl,
        'https://staging-api.trek.app',
      );
      expect(
        EnvironmentConfig.forEnvironment(Environment.prod).apiBaseUrl,
        'https://api.trek.app',
      );
    });

    test('fromName is case-insensitive', () {
      expect(EnvironmentConfig.fromName('DEV').environment, Environment.dev);
      expect(
        EnvironmentConfig.fromName('Staging').environment,
        Environment.staging,
      );
    });

    test('fromName falls back to prod for unknown or missing input', () {
      expect(
        EnvironmentConfig.fromName('nonsense').environment,
        Environment.prod,
      );
      expect(EnvironmentConfig.fromName(null).environment, Environment.prod);
      expect(EnvironmentConfig.fromName('').environment, Environment.prod);
    });
  });
}
