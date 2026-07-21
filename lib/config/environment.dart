/// The backend environment the app is currently pointed at.
enum Environment { dev, staging, prod }

/// Per-environment configuration (API base URL, feature flags).
///
/// The active environment defaults to [Environment.prod] but can be
/// overridden at build/run time via `--dart-define=TREK_ENV=dev|staging|prod`,
/// e.g. `flutter run --dart-define=TREK_ENV=staging`.
class EnvironmentConfig {
  const EnvironmentConfig._(this.environment, this.apiBaseUrl);

  final Environment environment;
  final String apiBaseUrl;

  static const Map<Environment, String> _baseUrls = {
    Environment.dev: 'https://dev-api.trek.app',
    Environment.staging: 'https://staging-api.trek.app',
    Environment.prod: 'https://api.trek.app',
  };

  factory EnvironmentConfig.forEnvironment(Environment environment) {
    return EnvironmentConfig._(environment, _baseUrls[environment]!);
  }

  /// Resolves the environment from a raw string (case-insensitive), falling
  /// back to [Environment.prod] for an unrecognized or missing value.
  factory EnvironmentConfig.fromName(String? name) {
    switch (name?.toLowerCase()) {
      case 'dev':
        return EnvironmentConfig.forEnvironment(Environment.dev);
      case 'staging':
        return EnvironmentConfig.forEnvironment(Environment.staging);
      case 'prod':
        return EnvironmentConfig.forEnvironment(Environment.prod);
      default:
        return EnvironmentConfig.forEnvironment(Environment.prod);
    }
  }

  /// The config selected via the `TREK_ENV` compile-time define.
  static final EnvironmentConfig current = EnvironmentConfig.fromName(
    const String.fromEnvironment('TREK_ENV'),
  );
}
