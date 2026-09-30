import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/home_widgets/widget_trip.dart';
import 'package:trek/home_widgets/widget_trip_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  const trips = [
    WidgetTrip(
      id: 1,
      title: 'Tokyo',
      startDate: '2026-10-01',
      endDate: '2026-10-09',
    ),
    WidgetTrip(id: 2, title: 'Undated'),
  ];

  test('round-trips a trip list per scope', () async {
    final store = PreferencesWidgetTripStore();
    await store.writeTrips('https://a.example#1', trips);

    expect(await store.readTrips('https://a.example#1'), trips);
    expect(await store.readTrips('https://a.example#2'), isNull);
  });

  test('treats a corrupt entry as a cache miss', () async {
    await SharedPreferencesAsync().setString(
      'trek.home_widget.trips.s',
      '{not json',
    );
    expect(await PreferencesWidgetTripStore().readTrips('s'), isNull);
  });
}
