import '../network/api_client.dart';
import 'addon_flags.dart';

/// `GET /api/addons` — the instance's enabled add-ons, Collab sub-features,
/// and bag-tracking flag. JWT-guarded, so it needs the authenticated client.
class AddonsApi {
  AddonsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AddonFlags> fetchFlags() async {
    final body = await _apiClient.get('/api/addons');
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Unexpected /api/addons response.');
    }
    try {
      return AddonFlags.fromJson(body);
    } on TypeError {
      throw const FormatException('Unexpected /api/addons response.');
    }
  }
}
