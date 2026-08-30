import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/transit/transit_local_store.dart';
import 'package:trek/transit/transit_models.dart';

void main() {
  late InMemorySharedPreferencesAsync backend;
  late PreferencesTransitLocalStore store;

  setUp(() {
    backend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backend;
    store = PreferencesTransitLocalStore();
  });

  TransitPlace place(String name) =>
      TransitPlace(name: name, lat: 1, lng: 2, type: 'STOP');

  test('read returns null for a key that was never written', () async {
    expect(await store.readStopSearch('nope'), isNull);
    expect(await store.readAirportSearch('nope'), isNull);
    expect(await store.readRoutePlan('nope'), isNull);
  });

  test('write then read round-trips stop results', () async {
    await store.writeStopSearch('welling', [
      place('Wellington'),
      place('Weka'),
    ]);

    final result = await store.readStopSearch('welling');

    expect(result?.map((p) => p.name), ['Wellington', 'Weka']);
  });

  test('an empty result list is distinct from "never fetched"', () async {
    await store.writeStopSearch('zzz', const []);

    expect(await store.readStopSearch('zzz'), isEmpty);
    expect(await store.readStopSearch('other'), isNull);
  });

  test('round-trips airport results and route plans', () async {
    await store.writeAirportSearch('akl', const [
      Airport(
        iata: 'AKL',
        name: 'Auckland',
        city: 'Auckland',
        country: 'NZ',
        lat: 1,
        lng: 2,
        tz: 'Pacific/Auckland',
      ),
    ]);
    await store.writeRoutePlan('k', const [
      TransitItinerary(startTime: 'a', endTime: 'b', duration: 600),
    ]);

    expect((await store.readAirportSearch('akl'))?.single.iata, 'AKL');
    expect((await store.readRoutePlan('k'))?.single.duration, 600);
  });

  test('evicts the oldest entry once past the 30-entry cap', () async {
    for (var i = 0; i < 35; i++) {
      await store.writeStopSearch('q$i', [place('Stop $i')]);
    }

    expect(await store.readStopSearch('q0'), isNull);
    expect(await store.readStopSearch('q4'), isNull);
    expect((await store.readStopSearch('q34'))?.single.name, 'Stop 34');
  });

  test('re-writing a key refreshes its recency', () async {
    for (var i = 0; i < 30; i++) {
      await store.writeStopSearch('q$i', [place('Stop $i')]);
    }
    // Touch q0 so it is no longer the oldest, then push one more in.
    await store.writeStopSearch('q0', [place('Stop 0 again')]);
    await store.writeStopSearch('q30', [place('Stop 30')]);

    expect((await store.readStopSearch('q0'))?.single.name, 'Stop 0 again');
    expect(await store.readStopSearch('q1'), isNull);
  });
}
