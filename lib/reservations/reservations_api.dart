import '../network/api_client.dart';
import 'reservation.dart';

/// Thin wrapper around `GET /api/trips/:tripId/reservations`. Confirmed
/// against Trek's actual `ReservationsController.list`: the response is
/// `{ reservations: [...] }` (never a bare array), the same wrapped-list
/// convention as `/api/trips/:tripId/accommodations`, ordered by
/// `reservation_time` ascending then `created_at`. A trip the caller can't
/// access is `404 { error: 'Trip not found' }`.
class ReservationsApi {
  ReservationsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Reservation>> listReservations(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/reservations')
            as Map<String, dynamic>;
    final json = response['reservations'] as List<dynamic>? ?? const [];
    return json
        .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
