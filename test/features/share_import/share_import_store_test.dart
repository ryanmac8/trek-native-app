import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/features/share_import/share_import_api.dart';
import 'package:trek/features/share_import/share_import_store.dart';
import 'package:trek/share_intake/shared_map_link.dart';

void main() {
  late PreferencesShareImportStore store;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = PreferencesShareImportStore();
  });

  test('trips round-trip per server', () async {
    await store.writeTrips('https://a.example.com', const [
      ShareTargetTrip(id: 1, title: 'A', startDate: '2026-11-01'),
    ]);

    final trips = await store.readTrips('https://a.example.com');
    expect(trips!.single.title, 'A');
    expect(trips.single.startDate, '2026-11-01');
    expect(trips.single.endDate, isNull);
    expect(await store.readTrips('https://b.example.com'), isNull);
  });

  test('pending imports round-trip', () async {
    await store.writePending(const [
      PendingPlaceImport(
        id: 'x',
        serverUrl: 'https://a.example.com',
        tripId: 20,
        tripTitle: 'New Zealand',
        url: 'https://maps.apple.com/?ll=1.5,2.5',
        provider: MapLinkProvider.apple,
        name: 'Pin',
        suggestedName: 'Suggested',
        lat: 1.5,
        lng: 2.5,
      ),
    ]);

    final item = (await store.readPending()).single;
    expect(item.id, 'x');
    expect(item.tripId, 20);
    expect(item.provider, MapLinkProvider.apple);
    expect(item.name, 'Pin');
    expect(item.suggestedName, 'Suggested');
    expect(item.lat, 1.5);
    expect(item.lng, 2.5);
  });

  test('empty and corrupt data read as nothing rather than throwing', () async {
    expect(await store.readPending(), isEmpty);

    final preferences = SharedPreferencesAsync();
    await preferences.setString('trek.share_import.pending', '{not json');
    await preferences.setString(
      'trek.share_import.trips.https://a.example.com',
      '[{"title": 3}]',
    );

    expect(await store.readPending(), isEmpty);
    expect(await store.readTrips('https://a.example.com'), isNull);
  });
}
