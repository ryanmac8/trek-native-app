import 'package:shared_preferences/shared_preferences.dart';

import 'app_permission.dart';

/// Remembers when the user last tapped "Not now" on a priming sheet, so
/// automatic (not user-initiated) priming doesn't nag. Device-local UI
/// state — not account data, never synced.
abstract class PrimingStorage {
  Future<DateTime?> declinedAt(AppPermission permission);

  Future<void> recordDecline(AppPermission permission, DateTime at);

  Future<void> clearDecline(AppPermission permission);
}

/// [PrimingStorage] backed by `shared_preferences`, one key per permission
/// (`trek.permission_priming.<name>.declined_at`, epoch milliseconds).
/// Storage failures are swallowed: a failed read means "never declined",
/// a failed write means the next automatic prime may show the sheet again
/// — both harmless.
class PreferencesPrimingStorage implements PrimingStorage {
  PreferencesPrimingStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String keyFor(AppPermission permission) =>
      'trek.permission_priming.${permission.name}.declined_at';

  @override
  Future<DateTime?> declinedAt(AppPermission permission) async {
    try {
      final millis = await _preferences.getInt(keyFor(permission));
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> recordDecline(AppPermission permission, DateTime at) async {
    try {
      await _preferences.setInt(
        keyFor(permission),
        at.toUtc().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  @override
  Future<void> clearDecline(AppPermission permission) async {
    try {
      await _preferences.remove(keyFor(permission));
    } catch (_) {}
  }
}
