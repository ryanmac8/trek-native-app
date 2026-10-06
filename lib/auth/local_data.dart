import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A piece of on-device data that belongs to the signed-in account — a
/// feature's local cache, a pending-write queue, etc. Registered with
/// [LocalDataRegistry] so it is wiped on logout and when a different account
/// signs in on the same device.
abstract class AccountScopedData {
  /// Short label used in diagnostics when [clear] fails (e.g. `trips cache`).
  String get name;

  /// Removes everything this store holds for the current account.
  Future<void> clear();

  /// Number of local changes not yet written to the server. These are lost
  /// by [clear]; the logout UI uses the total to warn before discarding
  /// them. Stores with no outgoing writes keep the default of `0`.
  Future<int> unsyncedChangeCount() async => 0;
}

/// A store whose [AccountScopedData.clear] threw during
/// [LocalDataRegistry.clearAll].
class LocalDataClearFailure {
  const LocalDataClearFailure(this.name, this.error);

  final String name;
  final Object error;

  @override
  String toString() => 'LocalDataClearFailure($name: $error)';
}

/// The set of [AccountScopedData] stores on this device. Each feature that
/// persists account data registers its store here (typically from the
/// provider that creates it), and [AuthService] clears them all on logout
/// and on an account switch.
class LocalDataRegistry {
  final List<AccountScopedData> _stores = [];

  List<AccountScopedData> get stores => List.unmodifiable(_stores);

  void register(AccountScopedData store) {
    if (!_stores.contains(store)) _stores.add(store);
  }

  void unregister(AccountScopedData store) => _stores.remove(store);

  /// Clears every registered store. Never throws: one store failing does not
  /// stop the others from being cleared, and the failures are returned so
  /// callers can report them.
  Future<List<LocalDataClearFailure>> clearAll() async {
    final failures = <LocalDataClearFailure>[];
    for (final store in List.of(_stores)) {
      try {
        await store.clear();
      } on Object catch (error) {
        debugPrint('Failed to clear local data "${store.name}": $error');
        failures.add(LocalDataClearFailure(store.name, error));
      }
    }
    return failures;
  }

  /// Total unsynced changes across all stores. A store that fails to report
  /// counts as `0` — the count only drives a warning, never a block.
  Future<int> unsyncedChangeCount() async {
    var total = 0;
    for (final store in List.of(_stores)) {
      try {
        total += await store.unsyncedChangeCount();
      } on Object catch (error) {
        debugPrint('Failed to count unsynced "${store.name}": $error');
      }
    }
    return total;
  }
}

/// Identifies which account the data in [LocalDataRegistry] belongs to: the
/// server's public URL plus the Trek user id from the session JWT's `id`
/// claim. Compared on every login to detect an account switch.
@immutable
class LocalDataOwner {
  const LocalDataOwner({required this.serverUrl, required this.userId});

  /// Parses the form written by [encode]; `null` for anything malformed.
  static LocalDataOwner? decode(String value) {
    final separator = value.lastIndexOf('#');
    if (separator <= 0) return null;
    final userId = int.tryParse(value.substring(separator + 1));
    if (userId == null) return null;
    return LocalDataOwner(
      serverUrl: value.substring(0, separator),
      userId: userId,
    );
  }

  final String serverUrl;
  final int userId;

  String encode() => '$serverUrl#$userId';

  @override
  bool operator ==(Object other) =>
      other is LocalDataOwner &&
      other.serverUrl == serverUrl &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(serverUrl, userId);

  @override
  String toString() => 'LocalDataOwner(${encode()})';
}

/// Persists the [LocalDataOwner] of the data currently on the device.
abstract class LocalDataOwnerStorage {
  Future<LocalDataOwner?> read();
  Future<void> write(LocalDataOwner owner);
  Future<void> clear();
}

/// Stores the [LocalDataOwner] in `shared_preferences` — a server URL and a
/// numeric user id, neither of which is a secret.
class PreferencesLocalDataOwnerStorage implements LocalDataOwnerStorage {
  PreferencesLocalDataOwnerStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _ownerKey = 'trek.local_data.owner';

  final SharedPreferencesAsync _preferences;

  @override
  Future<LocalDataOwner?> read() async {
    final value = await _preferences.getString(_ownerKey);
    return value == null ? null : LocalDataOwner.decode(value);
  }

  @override
  Future<void> write(LocalDataOwner owner) =>
      _preferences.setString(_ownerKey, owner.encode());

  @override
  Future<void> clear() => _preferences.remove(_ownerKey);
}
