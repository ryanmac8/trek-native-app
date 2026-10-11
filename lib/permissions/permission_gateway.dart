import 'package:permission_handler/permission_handler.dart' as ph;

import 'app_permission.dart';

/// The OS's answer for an [AppPermission], collapsed to what the priming
/// flow needs to branch on.
enum AppPermissionStatus {
  /// Granted (including iOS "limited"/"provisional" grants).
  granted,

  /// Not granted, but the OS will still show its prompt if asked — either
  /// never asked yet, or (Android) denied once without "don't ask again".
  denied,

  /// The user refused and the OS won't prompt again; only Settings can
  /// change it.
  permanentlyDenied,

  /// Blocked by parental controls / device management; the user can't
  /// change it either.
  restricted,
}

/// Reads and requests OS permissions. The real implementation is a thin
/// wrapper over `permission_handler`; tests substitute a fake.
abstract class PermissionGateway {
  Future<AppPermissionStatus> status(AppPermission permission);

  /// Shows the OS permission prompt (if the OS still allows one) and
  /// returns the resulting status.
  Future<AppPermissionStatus> request(AppPermission permission);

  /// Opens this app's page in the system Settings app. Returns `false` if
  /// it couldn't be opened.
  Future<bool> openSettings();
}

/// [PermissionGateway] backed by `permission_handler`. Platform errors (a
/// missing plugin registration, an undeclared permission) are reported as
/// [AppPermissionStatus.denied] rather than thrown — callers treat a
/// missing permission as "feature unavailable", never as a crash.
class DevicePermissionGateway implements PermissionGateway {
  @override
  Future<AppPermissionStatus> status(AppPermission permission) async {
    try {
      return mapPermissionStatus(await _platformPermission(permission).status);
    } catch (_) {
      return AppPermissionStatus.denied;
    }
  }

  @override
  Future<AppPermissionStatus> request(AppPermission permission) async {
    try {
      return mapPermissionStatus(
        await _platformPermission(permission).request(),
      );
    } catch (_) {
      return AppPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  static ph.Permission _platformPermission(AppPermission permission) {
    return switch (permission) {
      AppPermission.location => ph.Permission.locationWhenInUse,
    };
  }
}

/// Maps `permission_handler`'s status onto [AppPermissionStatus].
AppPermissionStatus mapPermissionStatus(ph.PermissionStatus status) {
  return switch (status) {
    ph.PermissionStatus.granted ||
    ph.PermissionStatus.limited ||
    ph.PermissionStatus.provisional => AppPermissionStatus.granted,
    ph.PermissionStatus.denied => AppPermissionStatus.denied,
    ph.PermissionStatus.permanentlyDenied =>
      AppPermissionStatus.permanentlyDenied,
    ph.PermissionStatus.restricted => AppPermissionStatus.restricted,
  };
}
