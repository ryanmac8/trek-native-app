/// Which of Trek's subscribable ICS feeds a [CalendarFeedSnapshot] is for:
/// the per-user "All trips" feed, or a single trip's feed.
sealed class CalendarFeedScope {
  const CalendarFeedScope();

  /// Token-management endpoint for this feed. `GET` reads the current
  /// `{ feed_url }`, `POST` enables (idempotent), `PUT` rotates, `DELETE`
  /// disables.
  String get tokenPath;

  /// Stable key for this feed in the local cache.
  String get cacheKey;
}

class AllTripsFeedScope extends CalendarFeedScope {
  const AllTripsFeedScope();

  @override
  String get tokenPath => '/api/feed/user/token';

  @override
  String get cacheKey => 'user';

  @override
  bool operator ==(Object other) => other is AllTripsFeedScope;

  @override
  int get hashCode => (AllTripsFeedScope).hashCode;
}

class TripFeedScope extends CalendarFeedScope {
  const TripFeedScope(this.tripId);

  final String tripId;

  @override
  String get tokenPath => '/api/trips/$tripId/feed/token';

  @override
  String get cacheKey => 'trip.$tripId';

  @override
  bool operator ==(Object other) =>
      other is TripFeedScope && other.tripId == tripId;

  @override
  int get hashCode => tripId.hashCode;
}

/// A token-management change the user asked for that hasn't reached the
/// server yet.
enum CalendarFeedAction { enable, rotate, disable }

/// The locally cached state of one calendar feed: the last feed URL the
/// server returned, plus at most one not-yet-synced [pending] action.
///
/// Only one action is ever pending — a newer request replaces an older
/// one, since each of enable/rotate/disable fully determines the end state.
class CalendarFeedSnapshot {
  const CalendarFeedSnapshot({this.feedUrl, this.pending, this.syncedAt});

  static const empty = CalendarFeedSnapshot();

  /// The subscribable `https://…/api/feed/{trip|user}/<token>.ics` URL, or
  /// `null` when the feed is off (or not yet known).
  final String? feedUrl;

  final CalendarFeedAction? pending;

  /// When [feedUrl] was last confirmed by the server.
  final DateTime? syncedAt;

  /// Whether the feed is on, as far as the user is concerned — a pending
  /// action wins over the last server state.
  bool get isEnabled => switch (pending) {
    CalendarFeedAction.enable || CalendarFeedAction.rotate => true,
    CalendarFeedAction.disable => false,
    null => feedUrl != null,
  };

  /// The URL that's safe to hand to a calendar app right now. `null` while
  /// any action is pending: an enable has no URL yet, and a rotate is about
  /// to invalidate the cached one.
  String? get subscribableUrl => pending == null ? feedUrl : null;

  CalendarFeedSnapshot withPending(CalendarFeedAction action) =>
      CalendarFeedSnapshot(
        // Disabling takes effect locally straight away; the other actions
        // need the server to mint a token.
        feedUrl: action == CalendarFeedAction.disable ? null : feedUrl,
        pending: action,
        syncedAt: syncedAt,
      );

  Map<String, dynamic> toJson() => {
    'feed_url': feedUrl,
    'pending': pending?.name,
    'synced_at': syncedAt?.toIso8601String(),
  };

  factory CalendarFeedSnapshot.fromJson(Map<String, dynamic> json) {
    final pending = json['pending'];
    final syncedAt = json['synced_at'];
    return CalendarFeedSnapshot(
      feedUrl: json['feed_url'] as String?,
      pending: pending is String
          ? CalendarFeedAction.values.asNameMap()[pending]
          : null,
      syncedAt: syncedAt is String ? DateTime.tryParse(syncedAt) : null,
    );
  }
}
