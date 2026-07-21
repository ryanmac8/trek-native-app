import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/auth/auth_tokens.dart';
import 'package:trek/auth/token_storage.dart';

/// Fake handler for the `flutter_secure_storage` plugin channel, standing in
/// for the iOS Keychain / Android Keystore in tests. Mirrors the real
/// plugin's method names/args so [SecureTokenStorage] can be tested without
/// a device.
class _FakeSecureStorageBackend {
  final Map<String, String> _values = {};

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'read':
        return _values[call.arguments['key']];
      case 'write':
        _values[call.arguments['key']] = call.arguments['value'] as String;
        return null;
      case 'delete':
        _values.remove(call.arguments['key']);
        return null;
      case 'containsKey':
        return _values.containsKey(call.arguments['key']);
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late _FakeSecureStorageBackend backend;

  setUp(() {
    backend = _FakeSecureStorageBackend();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, backend.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SecureTokenStorage', () {
    test('read() returns null when nothing has been stored', () async {
      final storage = SecureTokenStorage();

      expect(await storage.read(), isNull);
    });

    test('write() then read() round-trips the tokens', () async {
      final storage = SecureTokenStorage();
      final tokens = AuthTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.utc(2030, 1, 1),
      );

      await storage.write(tokens);
      final result = await storage.read();

      expect(result?.accessToken, 'access-1');
      expect(result?.refreshToken, 'refresh-1');
      expect(result?.expiresAt, DateTime.utc(2030, 1, 1));
    });

    test('clear() removes stored tokens', () async {
      final storage = SecureTokenStorage();
      await storage.write(
        AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.utc(2030, 1, 1),
        ),
      );

      await storage.clear();

      expect(await storage.read(), isNull);
    });
  });
}
