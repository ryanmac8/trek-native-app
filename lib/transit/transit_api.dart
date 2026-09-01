import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'transit_models.dart';

/// Wraps Trek's transit + airport search endpoints. All of them are
/// JWT-guarded (`TransitController`, `AirportsController`), so this uses the
/// authenticated [ApiClient] (`apiClientProvider`).
///
/// This is a thin transport layer: it does no caching and no offline
/// handling — [TransitRepository] is the offline-first front door screens
/// use. See docs/transit.md.
class TransitApi {
  TransitApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/transit/geocode?q=&lang=&near=` — station / place search for
  /// the route pickers. The server returns `[]` for a query shorter than 2
  /// characters, so callers don't need to guard.
  ///
  /// [near] biases results towards a `"lat,lng"` point.
  Future<List<TransitPlace>> searchStops(
    String query, {
    String? near,
    String? language,
  }) async {
    final response =
        await _apiClient.get(
              '/api/transit/geocode',
              query: {'q': query, 'lang': ?language, 'near': ?near},
            )
            as Map<String, dynamic>;

    final rows = response['results'] as List<dynamic>? ?? const [];
    return rows
        .map((e) => TransitPlace.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /api/transit/plan` — public-transit journeys between two
  /// `"lat,lng"` points. Returns the itineraries in the provider's order
  /// (soonest / best first).
  Future<List<TransitItinerary>> planRoute(TransitPlanQuery query) async {
    final response =
        await _apiClient.get(
              '/api/transit/plan',
              query: query.toQueryParameters(),
            )
            as Map<String, dynamic>;

    final rows = response['itineraries'] as List<dynamic>? ?? const [];
    return rows
        .map((e) => TransitItinerary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /api/airports/search?q=` — typeahead over the bundled airport
  /// dataset. The server returns `[]` for a missing / empty query.
  Future<List<Airport>> searchAirports(String query) async {
    final response =
        await _apiClient.get('/api/airports/search', query: {'q': query})
            as List<dynamic>;

    return response
        .map((e) => Airport.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /api/airports/:iata` — single lookup by IATA code. Returns null
  /// when the server 404s (`{ error: 'Airport not found' }`).
  Future<Airport?> lookupAirport(String iata) async {
    try {
      final response =
          await _apiClient.get('/api/airports/${iata.toUpperCase()}')
              as Map<String, dynamic>;
      return Airport.fromJson(response);
    } on ServerException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
