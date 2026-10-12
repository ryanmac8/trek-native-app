import '../../network/api_client.dart';

/// The fields of a trip the share-import picker needs — a subset of Trek's
/// `GET /api/trips` row (`TRIP_SELECT` in `server/src/nest/trips/`).
class ShareTargetTrip {
  const ShareTargetTrip({
    required this.id,
    required this.title,
    this.startDate,
    this.endDate,
  });

  factory ShareTargetTrip.fromJson(Map<String, dynamic> json) {
    return ShareTargetTrip(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
    );
  }

  final int id;
  final String title;

  /// `YYYY-MM-DD`, or `null` for an undated trip.
  final String? startDate;
  final String? endDate;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start_date': startDate,
    'end_date': endDate,
  };
}

/// `POST /api/maps/resolve-url` → `{lat, lng, name, address, google_ftid}`.
class ResolvedMapLink {
  const ResolvedMapLink({
    required this.lat,
    required this.lng,
    this.name,
    this.address,
    this.googleFtid,
  });

  factory ResolvedMapLink.fromJson(Map<String, dynamic> json) {
    return ResolvedMapLink(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      name: json['name'] as String?,
      address: json['address'] as String?,
      googleFtid: json['google_ftid'] as String?,
    );
  }

  final double lat;
  final double lng;
  final String? name;
  final String? address;
  final String? googleFtid;
}

/// The three Trek endpoints sharing a map link into a trip uses. All are
/// JWT-guarded, so [apiClient] must be the authenticated client.
class ShareImportApi {
  ShareImportApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/trips` — the caller's non-archived trips (owned or shared),
  /// newest first.
  Future<List<ShareTargetTrip>> listTrips() async {
    final response = await _apiClient.get('/api/trips') as Map<String, dynamic>;
    return (response['trips'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ShareTargetTrip.fromJson)
        .toList();
  }

  /// `POST /api/maps/resolve-url`. Follows Google/Amap short links on the
  /// server and reverse geocodes an address. A link with no extractable
  /// coordinate is a 400 (`ValidationException`); an SSRF-blocked one a 403.
  Future<ResolvedMapLink> resolveUrl(String url) async {
    final response =
        await _apiClient.post('/api/maps/resolve-url', body: {'url': url})
            as Map<String, dynamic>;
    return ResolvedMapLink.fromJson(response);
  }

  /// `POST /api/trips/:tripId/places` → `201 {place}`. Returns the created
  /// place's id. 404 = trip gone or not shared with the caller; 403 = no
  /// `place_edit` permission on it.
  Future<int> createPlace(int tripId, Map<String, dynamic> body) async {
    final response =
        await _apiClient.post('/api/trips/$tripId/places', body: body)
            as Map<String, dynamic>;
    final place = response['place'] as Map<String, dynamic>;
    return (place['id'] as num).toInt();
  }
}
