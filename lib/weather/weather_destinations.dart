import 'weather_models.dart';

/// A small bundled set of well-known destinations, used only to give the
/// weather screen something to look up before the app has a real source of
/// coordinates.
///
/// Weather in Trek is always *for a place* — the web client reads `place.lat` /
/// `place.lng` off a trip's places. This app doesn't have trips, places
/// ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)), days
/// ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)), or geocoding
/// ([#17](https://github.com/ryanmac8/trek-native-app/issues/17)) yet, so this
/// list is the stand-in. When any of those land, the weather repository and
/// widgets take their coordinates from that data instead and this list can go
/// away.
///
/// Coordinates are approximate city-centre points, rounded to 2 dp — the same
/// precision the weather cache key uses.
const popularDestinations = <TravelDestination>[
  TravelDestination(
    name: 'Reykjavík',
    country: 'Iceland',
    point: GeoPoint(64.15, -21.94),
  ),
  TravelDestination(
    name: 'Lisbon',
    country: 'Portugal',
    point: GeoPoint(38.72, -9.14),
  ),
  TravelDestination(
    name: 'Barcelona',
    country: 'Spain',
    point: GeoPoint(41.39, 2.17),
  ),
  TravelDestination(
    name: 'Paris',
    country: 'France',
    point: GeoPoint(48.86, 2.35),
  ),
  TravelDestination(
    name: 'London',
    country: 'United Kingdom',
    point: GeoPoint(51.51, -0.13),
  ),
  TravelDestination(
    name: 'Amsterdam',
    country: 'Netherlands',
    point: GeoPoint(52.37, 4.90),
  ),
  TravelDestination(
    name: 'Berlin',
    country: 'Germany',
    point: GeoPoint(52.52, 13.40),
  ),
  TravelDestination(
    name: 'Rome',
    country: 'Italy',
    point: GeoPoint(41.90, 12.50),
  ),
  TravelDestination(
    name: 'Athens',
    country: 'Greece',
    point: GeoPoint(37.98, 23.73),
  ),
  TravelDestination(
    name: 'Istanbul',
    country: 'Türkiye',
    point: GeoPoint(41.01, 28.98),
  ),
  TravelDestination(
    name: 'Marrakesh',
    country: 'Morocco',
    point: GeoPoint(31.63, -7.99),
  ),
  TravelDestination(
    name: 'Cairo',
    country: 'Egypt',
    point: GeoPoint(30.04, 31.24),
  ),
  TravelDestination(
    name: 'Cape Town',
    country: 'South Africa',
    point: GeoPoint(-33.92, 18.42),
  ),
  TravelDestination(
    name: 'Dubai',
    country: 'United Arab Emirates',
    point: GeoPoint(25.20, 55.27),
  ),
  TravelDestination(
    name: 'Mumbai',
    country: 'India',
    point: GeoPoint(19.08, 72.88),
  ),
  TravelDestination(
    name: 'Bangkok',
    country: 'Thailand',
    point: GeoPoint(13.75, 100.50),
  ),
  TravelDestination(
    name: 'Singapore',
    country: 'Singapore',
    point: GeoPoint(1.35, 103.82),
  ),
  TravelDestination(
    name: 'Tokyo',
    country: 'Japan',
    point: GeoPoint(35.68, 139.69),
  ),
  TravelDestination(
    name: 'Seoul',
    country: 'South Korea',
    point: GeoPoint(37.57, 126.98),
  ),
  TravelDestination(
    name: 'Sydney',
    country: 'Australia',
    point: GeoPoint(-33.87, 151.21),
  ),
  TravelDestination(
    name: 'Auckland',
    country: 'New Zealand',
    point: GeoPoint(-36.85, 174.76),
  ),
  TravelDestination(
    name: 'New York',
    country: 'United States',
    point: GeoPoint(40.71, -74.01),
  ),
  TravelDestination(
    name: 'Mexico City',
    country: 'Mexico',
    point: GeoPoint(19.43, -99.13),
  ),
  TravelDestination(
    name: 'Rio de Janeiro',
    country: 'Brazil',
    point: GeoPoint(-22.91, -43.17),
  ),
  TravelDestination(
    name: 'Buenos Aires',
    country: 'Argentina',
    point: GeoPoint(-34.60, -58.38),
  ),
  TravelDestination(
    name: 'Vancouver',
    country: 'Canada',
    point: GeoPoint(49.28, -123.12),
  ),
];
