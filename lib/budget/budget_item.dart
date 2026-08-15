/// A trip's budget line item, as returned by
/// `GET /api/trips/:tripId/budget` / `POST /api/trips/:tripId/budget`, plus
/// the fields needed to track an offline-created item until it syncs (see
/// [BudgetRepository] in `budget_repository.dart`).
///
/// The real response also carries `members`/`payers` (per-person splits and
/// who paid what) and settlement-related fields (`paid_by_user_id`,
/// `reservation_id`, `exchange_rate`) — confirmed against Trek's actual
/// `budget_items` schema and `BudgetController`/`budgetService.ts`
/// (`server/src/nest/budget/`, `server/src/services/budgetService.ts`).
/// This first slice of issue #7 only needs what the list row renders: name,
/// category, total price/currency, and note. Splits, payers, and
/// settlements are a follow-up once this exists to attach them to.
///
/// [id] is null exactly when the item was created locally while offline and
/// hasn't been confirmed by the server yet ([isPending]). [localId] is a
/// stable client-generated key that survives that transition — used to find
/// and replace the pending entry in the local cache once the create syncs,
/// without depending on the server id existing yet. Mirrors [Tag]'s
/// pending-write shape.
class BudgetItem {
  const BudgetItem({
    this.id,
    required this.localId,
    required this.tripId,
    required this.name,
    this.category,
    this.totalPrice,
    this.currency,
    this.persons,
    this.days,
    this.note,
    this.expenseDate,
  });

  final int? id;
  final String localId;
  final String tripId;
  final String name;

  /// Falls back server-side to `'other'` when omitted on create, so that
  /// default isn't replicated client-side.
  final String? category;

  /// Trek's `total_price` column — defaults to `0` server-side when
  /// omitted on create.
  final double? totalPrice;
  final String? currency;
  final int? persons;
  final int? days;
  final String? note;
  final String? expenseDate;

  /// True for an item created locally that hasn't been confirmed by the
  /// server yet — either still queued (offline) or its create request is in
  /// flight. See [BudgetRepository.createItem].
  bool get isPending => id == null;

  factory BudgetItem.fromJson(
    Map<String, dynamic> json, {
    required String tripId,
  }) {
    final id = json['id'] as int;
    return BudgetItem(
      id: id,
      localId: 'server-$id',
      tripId: tripId,
      name: json['name'] as String,
      category: json['category'] as String?,
      totalPrice: (json['total_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      persons: json['persons'] as int?,
      days: json['days'] as int?,
      note: json['note'] as String?,
      expenseDate: json['expense_date'] as String?,
    );
  }

  /// Round-trips a [BudgetItem] through the local cache (see
  /// `PreferencesBudgetLocalStore`) — unlike [fromJson]/the real API shape,
  /// this must also carry [id] being absent (a still-pending item) and the
  /// client-generated [localId].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'trip_id': tripId,
    'name': name,
    'category': category,
    'total_price': totalPrice,
    'currency': currency,
    'persons': persons,
    'days': days,
    'note': note,
    'expense_date': expenseDate,
  };

  factory BudgetItem.fromCacheJson(Map<String, dynamic> json) {
    return BudgetItem(
      id: json['id'] as int?,
      localId: json['local_id'] as String,
      tripId: json['trip_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      totalPrice: (json['total_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      persons: json['persons'] as int?,
      days: json['days'] as int?,
      note: json['note'] as String?,
      expenseDate: json['expense_date'] as String?,
    );
  }
}
