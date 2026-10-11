import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:trek/permissions/app_permission.dart';
import 'package:trek/permissions/permission_gateway.dart';

void main() {
  group('mapPermissionStatus', () {
    test('collapses permission_handler statuses', () {
      expect(
        mapPermissionStatus(ph.PermissionStatus.granted),
        AppPermissionStatus.granted,
      );
      expect(
        mapPermissionStatus(ph.PermissionStatus.limited),
        AppPermissionStatus.granted,
      );
      expect(
        mapPermissionStatus(ph.PermissionStatus.provisional),
        AppPermissionStatus.granted,
      );
      expect(
        mapPermissionStatus(ph.PermissionStatus.denied),
        AppPermissionStatus.denied,
      );
      expect(
        mapPermissionStatus(ph.PermissionStatus.permanentlyDenied),
        AppPermissionStatus.permanentlyDenied,
      );
      expect(
        mapPermissionStatus(ph.PermissionStatus.restricted),
        AppPermissionStatus.restricted,
      );
    });
  });

  group('DevicePermissionGateway', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('platform errors read as denied instead of throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'boom');
          });
      final gateway = DevicePermissionGateway();

      expect(
        await gateway.status(AppPermission.location),
        AppPermissionStatus.denied,
      );
      expect(
        await gateway.request(AppPermission.location),
        AppPermissionStatus.denied,
      );
      expect(await gateway.openSettings(), isFalse);
    });
  });
}
