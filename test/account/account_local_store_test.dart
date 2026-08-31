import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/account/account_local_store.dart';
import 'package:trek/account/account_models.dart';

void main() {
  late InMemorySharedPreferencesAsync backend;
  late PreferencesAccountLocalStore store;

  setUp(() {
    backend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backend;
    store = PreferencesAccountLocalStore();
  });

  const account = TrekAccount(
    id: 7,
    username: 'ada',
    email: 'ada@example.com',
    role: 'admin',
    avatarUrl: 'https://trek.example.com/a/7.png',
    mfaEnabled: true,
  );

  test('read returns null before anything is written', () async {
    expect(await store.read(), isNull);
  });

  test('write then read round-trips the account', () async {
    await store.write(account);

    final loaded = await store.read();

    expect(loaded?.id, 7);
    expect(loaded?.username, 'ada');
    expect(loaded?.role, 'admin');
    expect(loaded?.mfaEnabled, isTrue);
    expect(loaded?.avatarUrl, 'https://trek.example.com/a/7.png');
  });

  test('round-trips a createdAt timestamp', () async {
    final withDate = TrekAccount(
      id: 1,
      username: 'x',
      email: 'x@y.z',
      createdAt: DateTime.utc(2024, 6, 1),
    );

    await store.write(withDate);

    expect((await store.read())?.createdAt, DateTime.utc(2024, 6, 1));
  });

  test('clear drops the cached account', () async {
    await store.write(account);
    await store.clear();

    expect(await store.read(), isNull);
  });
}
