import '../network/api_client.dart';
import 'budget_item.dart';

/// Thin wrapper around `GET /api/trips/:tripId/budget` and
/// `POST /api/trips/:tripId/budget`. Confirmed live against Trek's actual
/// `BudgetController`: both the list and create responses are wrapped
/// (`{ items: [...] }` / `{ item }`), matching the same convention as
/// `/api/trips/:tripId/places` and `/api/tags`.
class BudgetApi {
  BudgetApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<BudgetItem>> listItems(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/budget')
            as Map<String, dynamic>;
    final itemsJson = response['items'] as List<dynamic>? ?? const [];
    return itemsJson
        .map(
          (json) =>
              BudgetItem.fromJson(json as Map<String, dynamic>, tripId: tripId),
        )
        .toList();
  }

  /// `POST /api/trips/:tripId/budget`. Only [name] is required — the server
  /// falls back to `'other'` for `category` and `0` for `total_price` when
  /// omitted, so those defaults aren't replicated client-side. Splits
  /// (`payers`/`members`) aren't sent by this first slice.
  Future<BudgetItem> createItem(
    String tripId, {
    required String name,
    String? category,
    double? totalPrice,
    int? persons,
    int? days,
    String? note,
    String? expenseDate,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (category != null && category.isNotEmpty) 'category': category,
      'total_price': ?totalPrice,
      'persons': ?persons,
      'days': ?days,
      if (note != null && note.isNotEmpty) 'note': note,
      if (expenseDate != null && expenseDate.isNotEmpty)
        'expense_date': expenseDate,
    };
    final response =
        await _apiClient.post('/api/trips/$tripId/budget', body: body)
            as Map<String, dynamic>;
    return BudgetItem.fromJson(
      response['item'] as Map<String, dynamic>,
      tripId: tripId,
    );
  }
}
