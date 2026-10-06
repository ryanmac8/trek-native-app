import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/auth/local_data.dart';

import '../test_helpers.dart';

void main() {
  group('LocalDataRegistry.clearAll', () {
    test('clears every registered store', () async {
      final trips = FakeAccountScopedData(name: 'trips');
      final todos = FakeAccountScopedData(name: 'todos');
      final registry = LocalDataRegistry()
        ..register(trips)
        ..register(todos);

      final failures = await registry.clearAll();

      expect(failures, isEmpty);
      expect(trips.wasCleared, isTrue);
      expect(todos.wasCleared, isTrue);
    });

    test('keeps clearing after one store fails, and reports it', () async {
      final broken = FakeAccountScopedData(name: 'broken', failOnClear: true);
      final todos = FakeAccountScopedData(name: 'todos');
      final registry = LocalDataRegistry()
        ..register(broken)
        ..register(todos);

      final failures = await registry.clearAll();

      expect(failures.map((f) => f.name), ['broken']);
      expect(failures.single.error, isA<StateError>());
      expect(todos.wasCleared, isTrue);
    });

    test('ignores duplicate registrations and honours unregister', () async {
      final trips = FakeAccountScopedData(name: 'trips');
      final todos = FakeAccountScopedData(name: 'todos');
      final registry = LocalDataRegistry()
        ..register(trips)
        ..register(trips)
        ..register(todos)
        ..unregister(todos);

      await registry.clearAll();

      expect(registry.stores, [trips]);
      expect(trips.clearCount, 1);
      expect(todos.wasCleared, isFalse);
    });
  });

  group('LocalDataRegistry.unsyncedChangeCount', () {
    test('sums every store', () async {
      final registry = LocalDataRegistry()
        ..register(FakeAccountScopedData(unsynced: 2))
        ..register(FakeAccountScopedData(unsynced: 3))
        ..register(FakeAccountScopedData());

      expect(await registry.unsyncedChangeCount(), 5);
    });

    test('defaults to 0 for stores without outgoing writes', () async {
      final registry = LocalDataRegistry()..register(_ReadOnlyCache());

      expect(await registry.unsyncedChangeCount(), 0);
    });

    test('counts a store that throws as 0', () async {
      final registry = LocalDataRegistry()
        ..register(_ThrowingCountStore())
        ..register(FakeAccountScopedData(unsynced: 1));

      expect(await registry.unsyncedChangeCount(), 1);
    });
  });

  group('LocalDataOwner', () {
    test('encode/decode round-trips', () {
      const owner = LocalDataOwner(
        serverUrl: 'https://trek.example.com',
        userId: 42,
      );

      expect(LocalDataOwner.decode(owner.encode()), owner);
    });

    test('decodes a server URL that itself contains #', () {
      expect(
        LocalDataOwner.decode('https://trek.example.com/#/x#7'),
        const LocalDataOwner(
          serverUrl: 'https://trek.example.com/#/x',
          userId: 7,
        ),
      );
    });

    test('decode returns null for malformed values', () {
      expect(LocalDataOwner.decode(''), isNull);
      expect(LocalDataOwner.decode('https://trek.example.com'), isNull);
      expect(LocalDataOwner.decode('https://trek.example.com#abc'), isNull);
      expect(LocalDataOwner.decode('#5'), isNull);
    });

    test('differs by server or by user', () {
      const owner = LocalDataOwner(serverUrl: 'https://a.example', userId: 1);

      expect(
        owner,
        isNot(const LocalDataOwner(serverUrl: 'https://b.example', userId: 1)),
      );
      expect(
        owner,
        isNot(const LocalDataOwner(serverUrl: 'https://a.example', userId: 2)),
      );
    });
  });

  group('PreferencesLocalDataOwnerStorage', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('reads null when nothing is stored', () async {
      expect(await PreferencesLocalDataOwnerStorage().read(), isNull);
    });

    test('writes, reads back, and clears the owner', () async {
      final storage = PreferencesLocalDataOwnerStorage();
      const owner = LocalDataOwner(
        serverUrl: 'https://trek.example.com',
        userId: 3,
      );

      await storage.write(owner);
      expect(await storage.read(), owner);

      await storage.clear();
      expect(await storage.read(), isNull);
    });
  });
}

class _ReadOnlyCache extends AccountScopedData {
  @override
  String get name => 'read-only cache';

  @override
  Future<void> clear() async {}
}

class _ThrowingCountStore extends AccountScopedData {
  @override
  String get name => 'throwing count';

  @override
  Future<void> clear() async {}

  @override
  Future<int> unsyncedChangeCount() async =>
      throw StateError('simulated count failure');
}
