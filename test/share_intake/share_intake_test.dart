import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/share_intake/share_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('trek/share_intake');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('takeInitialShare returns the text the native side holds', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getInitialShare');
      return 'https://maps.app.goo.gl/abc';
    });

    final intake = MethodChannelShareIntake();

    expect(await intake.takeInitialShare(), 'https://maps.app.goo.gl/abc');
  });

  test('takeInitialShare returns null where no handler exists (iOS)', () async {
    final intake = MethodChannelShareIntake();

    expect(await intake.takeInitialShare(), isNull);
  });

  test('takeInitialShare returns null on a platform error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });

    expect(await MethodChannelShareIntake().takeInitialShare(), isNull);
  });

  test('onShare calls from native are emitted on shares', () async {
    final intake = MethodChannelShareIntake();
    final received = <String>[];
    intake.shares.listen(received.add);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onShare', 'https://maps.apple.com/?ll=1.0,2.0'),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, ['https://maps.apple.com/?ll=1.0,2.0']);
  });
}
