/// One cached server response, as persisted by a [CacheStore].
///
/// [data] is the JSON-safe body (maps, lists, strings, numbers, bools,
/// null) — the same shape the server sent, or a feature's local edit of it.
class CacheEntry {
  const CacheEntry({
    required this.data,
    required this.fetchedAt,
    required this.schemaVersion,
    this.etag,
    this.invalidated = false,
  });

  final Object? data;

  /// When the server last confirmed this data: a 200 that delivered it, or a
  /// 304 that revalidated it. A local edit doesn't move it.
  final DateTime fetchedAt;

  /// The `CachePolicy.schemaVersion` the data was written under. An entry
  /// from a different version is discarded instead of decoded.
  final int schemaVersion;

  /// The response's `ETag`, sent back as `If-None-Match` on revalidation.
  /// `null` after a local edit, so the next revalidation downloads the full
  /// body instead of confirming the pre-edit version.
  final String? etag;

  /// Marked stale explicitly (e.g. after a write to the same data synced),
  /// regardless of its age.
  final bool invalidated;

  CacheEntry copyWith({
    Object? data,
    DateTime? fetchedAt,
    String? Function()? etag,
    bool? invalidated,
  }) {
    return CacheEntry(
      data: data ?? this.data,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      schemaVersion: schemaVersion,
      etag: etag == null ? this.etag : etag(),
      invalidated: invalidated ?? this.invalidated,
    );
  }

  Map<String, dynamic> toJson() => {
    'data': data,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'schema': schemaVersion,
    if (etag != null) 'etag': etag,
    if (invalidated) 'invalidated': true,
  };

  /// Throws [FormatException] if [json] isn't an entry written by [toJson].
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    final fetchedAt = json['fetchedAt'];
    final schema = json['schema'];
    final etag = json['etag'];
    if (fetchedAt is! String ||
        schema is! int ||
        (etag != null && etag is! String)) {
      throw const FormatException('Not a cache entry.');
    }
    return CacheEntry(
      data: json['data'],
      fetchedAt: DateTime.parse(fetchedAt),
      schemaVersion: schema,
      etag: etag as String?,
      invalidated: json['invalidated'] == true,
    );
  }
}
