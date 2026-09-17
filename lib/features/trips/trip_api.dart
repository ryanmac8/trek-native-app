import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'trip_models.dart';

/// Wraps Trek's trip endpoints.
///
/// Note: In Trek's backend, trip CRUD operations are protected by a
/// per-trip secret that can be shown in the trip dashboard. This API
/// wrapper handles both authenticated and unauthenticated requests
/// for read operations.
///
/// - `GET /api/trips` — public list, no auth required
/// - `GET /api/trips/:id` — read a specific trip, no auth required
/// - `POST /api/trips` — create a trip, requires auth
/// - `PATCH /api/trips/:id` — update a trip, requires auth
/// - `DELETE /api/trips/:id` — delete a trip, requires auth
///
/// For operations requiring auth, [ApiClient] must be authenticated
/// (apiClientProvider with token). See [TripRepository] for offline
/// caching logic.
class TripApi {
  TripApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/trips` — list all accessible trips.
  ///
  /// Returns `[results: List<Trip>]`. No auth required — the server returns
  /// the user's own trips and optionally others based on visibility
  /// settings.
  Future<List<Trip>> list() async {
    final response = await _apiClient.get('/api/trips')
        as Map<String, dynamic>;
    final results = response['results'] as List<dynamic>? ?? [];
    return results
        .map((e) => _tripFromList(e))
        .toList(growable: false);
  }

  /// `GET /api/trips/:id` — get a specific trip by ID.
  ///
  /// Returns `[trip: Trip]` or throws a 404 error if not found.
  Future<Trip?> getById(String id) async {
    try {
      final response = await _apiClient.get('/api/trips/$id')
          as Map<String, dynamic>;
      return _tripFromList(response);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// `POST /api/trips` — create a new trip.
  ///
  /// Returns `{ trip?: Trip, error?: string, requiresMfa?: boolean }`.
  /// On success, the response contains the created trip. On error, it
  /// contains an error message and may require MFA.
  Future<Trip?> create({
    required String title,
    String? description,
    String visibility = 'everyone',
    List<String> tags = const [],
    String? mfaToken,
  }) async {
    final response = await _apiClient.post('/api/trips', query: {
      'title': title,
      'description': description,
      'visibility': visibility,
      'tags': tags.join(','),
    }, mfaToken: mfaToken) as Map<String, dynamic>;

    final trip = response['trip'] != null
        ? _tripFromList(response['trip'])
        : null;
    final error = response['error'] as String? ?? null;
    final requiresMfa = response['requiresMfa'] as bool? ?? false;

    // If there's an error, rethrow
    if (error != null) {
      throw ApiError(code: error, message: 'Unable to create trip: $error');
    }

    return trip;
  }

  /// `PATCH /api/trips/:id` — update a trip.
  ///
  /// Returns `{ trip?: Trip, error?: string, requiresMfa?: boolean }`.
  Future<Trip?> update(String id, {
    String? title,
    String? description,
    String? visibility,
    List<String>? tags,
    String? mfaToken,
  }) async {
    final response = await _apiClient.patch('/api/trips/$id', query: {
      'title': title,
      'description': description,
      'visibility': visibility,
      'tags': tags?.join(','),
    }, mfaToken: mfaToken) as Map<String, dynamic>;

    final trip = response['trip'] != null
        ? _tripFromList(response['trip'])
        : null;
    final error = response['error'] as String? ?? null;
    final requiresMfa = response['requiresMfa'] as bool? ?? false;

    if (error != null) {
      throw ApiError(code: error, message: 'Unable to update trip: $error');
    }

    return trip;
  }

  /// `DELETE /api/trips/:id` — delete a trip.
  ///
  /// Returns `{ error?: string, success: boolean }`.
  Future<bool> delete(String id) async {
    try {
      await _apiClient.delete('/api/trips/$id');
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return false;
      if (e.statusCode == 403) return false;
      rethrow;
    }
    return false;
  }

  /// Helper: parse a trip from a list response (GET /api/trips).
  Trip _tripFromList(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: (json['description'] as dynamic?)?.toString(),
      visibility: json['visibility'] as String? ?? 'everyone',
      tags: (json['tags'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((t) => t.isNotEmpty)
          .toList() ?? [],
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    if (value is DateTime) return value;
    return null;
  }
}
