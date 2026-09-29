import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/features/trip_invites/pending_invite_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('round-trips invites through shared_preferences', () async {
    await PreferencesPendingInviteStore().put(
      const PendingInvite(
        token: 'tok',
        server: 'https://trek.example.com',
        acceptQueued: true,
        tripId: 20,
        tripTitle: 'New Zealand',
      ),
    );

    // A fresh instance reads what the first one wrote.
    final all = await PreferencesPendingInviteStore().readAll();
    expect(all, hasLength(1));
    expect(all.single.token, 'tok');
    expect(all.single.server, 'https://trek.example.com');
    expect(all.single.acceptQueued, isTrue);
    expect(all.single.tripId, 20);
    expect(all.single.tripTitle, 'New Zealand');
  });

  test('put replaces the entry with the same server and token', () async {
    final store = PreferencesPendingInviteStore();
    const invite = PendingInvite(token: 'tok', server: 'https://a.example');
    await store.put(invite);
    await store.put(
      const PendingInvite(token: 'tok', server: 'https://b.example'),
    );
    await store.put(invite.copyWith(acceptQueued: true));

    final all = await store.readAll();
    expect(all.map((e) => (e.server, e.acceptQueued)), [
      ('https://a.example', true),
      ('https://b.example', false),
    ]);
  });

  test('remove only drops the matching server + token', () async {
    final store = PreferencesPendingInviteStore();
    await store.put(
      const PendingInvite(token: 'tok', server: 'https://a.example'),
    );
    await store.put(
      const PendingInvite(token: 'tok', server: 'https://b.example'),
    );

    await store.remove(server: 'https://a.example', token: 'tok');

    expect((await store.readAll()).single.server, 'https://b.example');
  });

  test('recovers from corrupt stored data', () async {
    await SharedPreferencesAsync().setString(
      'trek.trip_invites.pending',
      'not json',
    );

    expect(await PreferencesPendingInviteStore().readAll(), isEmpty);
  });
}
