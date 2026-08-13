import '../network/api_client.dart';
import 'tag.dart';

/// Thin wrapper around `GET /api/tags` and `POST /api/tags`. Confirmed live
/// against Trek's actual `TagsController`/`tagSchema`: the list response is
/// `{ tags: [...] }` (never a bare array), matching the same wrapped-list
/// convention as `/api/trips` and `/api/trips/:tripId/places`. Unlike those,
/// tags aren't trip-scoped — they belong to the authenticated user.
class TagsApi {
  TagsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Tag>> listTags() async {
    final response = await _apiClient.get('/api/tags') as Map<String, dynamic>;
    final tagsJson = response['tags'] as List<dynamic>? ?? const [];
    return tagsJson
        .map((json) => Tag.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/tags`. Only [name] is required — the server falls back to
  /// `#10b981` for [color] when omitted, so that default isn't replicated
  /// client-side.
  Future<Tag> createTag({required String name, String? color}) async {
    final body = <String, dynamic>{
      'name': name,
      if (color != null && color.isNotEmpty) 'color': color,
    };
    final response =
        await _apiClient.post('/api/tags', body: body) as Map<String, dynamic>;
    return Tag.fromJson(response['tag'] as Map<String, dynamic>);
  }
}
