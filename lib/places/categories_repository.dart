import '../network/api_exception.dart';
import 'categories_api.dart';
import 'categories_local_store.dart';
import 'place.dart';

/// Offline-first access to the server's place categories: the cache is
/// what the category picker shows, refreshed from [CategoriesApi] when the
/// network allows. Read-only — categories are managed by server admins.
class CategoriesRepository {
  CategoriesRepository({
    required CategoriesApi categoriesApi,
    required CategoriesLocalStore localStore,
  }) : _categoriesApi = categoriesApi,
       _localStore = localStore;

  final CategoriesApi _categoriesApi;
  final CategoriesLocalStore _localStore;

  /// The cached list only — never touches the network.
  Future<List<PlaceCategoryRef>> cachedCategories() => _localStore.read();

  /// Fetches the list and replaces the cache with it. On
  /// [NetworkException] returns the cache instead, unless it's empty, in
  /// which case the exception propagates.
  Future<List<PlaceCategoryRef>> refreshCategories() async {
    try {
      final categories = await _categoriesApi.listCategories();
      await _localStore.write(categories);
      return categories;
    } on NetworkException {
      final cached = await _localStore.read();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }
}
