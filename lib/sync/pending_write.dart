/// One queued mutation in the [Outbox] — a write the user already made
/// locally that hasn't been confirmed by the server yet.
///
/// The outbox is feature-agnostic: [kind] names the [SyncHandler] that knows
/// how to push this write (e.g. `todo.update`), and [payload] is whatever
/// JSON-safe data that handler needs. Writes that share a [coalesceKey]
/// collapse into one queued write (see [Outbox.enqueue]).
class PendingWrite {
  const PendingWrite({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.coalesceKey,
    this.attempts = 0,
    this.lastError,
  });

  /// Locally generated, unique within the outbox.
  final String id;

  final String kind;
  final Map<String, dynamic> payload;

  /// Identifies the entity (and usually the operation) this write targets,
  /// e.g. `todo.update:42`. Null means the write never merges with another.
  final String? coalesceKey;

  final DateTime createdAt;

  /// How many times a push has failed with a transient server error (see
  /// [SyncFailure.transient]). Network failures don't count — being offline
  /// isn't the write's fault.
  final int attempts;

  /// Message of the most recent failed push, if any.
  final String? lastError;

  PendingWrite copyWith({
    Map<String, dynamic>? payload,
    int? attempts,
    String? lastError,
  }) {
    return PendingWrite(
      id: id,
      kind: kind,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      coalesceKey: coalesceKey,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'payload': payload,
    'coalesce_key': coalesceKey,
    'created_at': createdAt.toUtc().toIso8601String(),
    'attempts': attempts,
    'last_error': lastError,
  };

  factory PendingWrite.fromJson(Map<String, dynamic> json) {
    return PendingWrite(
      id: json['id'] as String,
      kind: json['kind'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      coalesceKey: json['coalesce_key'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}
