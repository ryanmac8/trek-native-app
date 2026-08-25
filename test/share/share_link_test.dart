import 'package:flutter_test/flutter_test.dart';
import 'package:trek/share/share_link.dart';

void main() {
  group('ShareLink.fromJson', () {
    test('parses a fully enabled share link', () {
      final link = ShareLink.fromJson({
        'token': 'abc123',
        'created_at': '2026-01-01T00:00:00.000Z',
        'share_map': true,
        'share_bookings': false,
        'share_packing': true,
        'share_budget': false,
        'share_collab': true,
      }, tripId: '20');

      expect(link.token, 'abc123');
      expect(link.createdAt, '2026-01-01T00:00:00.000Z');
      expect(link.shareBookings, isFalse);
      expect(link.sharePacking, isTrue);
      expect(link.shareCollab, isTrue);
      expect(link.tripId, '20');
      expect(link.isEnabled, isTrue);
    });

    test('a missing token means sharing has never been enabled', () {
      final link = ShareLink.fromJson({'token': null}, tripId: '20');

      expect(link.token, isNull);
      expect(link.isEnabled, isFalse);
    });

    test('share_map/share_bookings default true, the rest default false '
        'when omitted, matching the server', () {
      final link = ShareLink.fromJson({'token': 'abc123'}, tripId: '20');

      expect(link.shareMap, isTrue);
      expect(link.shareBookings, isTrue);
      expect(link.sharePacking, isFalse);
      expect(link.shareBudget, isFalse);
      expect(link.shareCollab, isFalse);
    });
  });

  group('isEnabled', () {
    test('true once a create/update is queued, even with no token yet', () {
      const link = ShareLink(tripId: '20', needsSync: true);

      expect(link.isEnabled, isTrue);
    });

    test('false once a disable is queued, even though the token is still '
        'cached for the retry', () {
      const link = ShareLink(
        tripId: '20',
        token: 'abc123',
        pendingDelete: true,
      );

      expect(link.isEnabled, isFalse);
    });

    test('false when there is no token and nothing is queued', () {
      const link = ShareLink(tripId: '20');

      expect(link.isEnabled, isFalse);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson()/fromCacheJson() preserves every field', () {
      const link = ShareLink(
        tripId: '20',
        token: 'abc123',
        createdAt: '2026-01-01T00:00:00.000Z',
        shareBookings: true,
        sharePacking: true,
        shareBudget: true,
        shareCollab: true,
        needsSync: true,
        pendingDelete: false,
      );

      final result = ShareLink.fromCacheJson(link.toCacheJson());

      expect(result.tripId, link.tripId);
      expect(result.token, link.token);
      expect(result.createdAt, link.createdAt);
      expect(result.shareMap, link.shareMap);
      expect(result.shareBookings, link.shareBookings);
      expect(result.sharePacking, link.sharePacking);
      expect(result.shareBudget, link.shareBudget);
      expect(result.shareCollab, link.shareCollab);
      expect(result.needsSync, link.needsSync);
      expect(result.pendingDelete, link.pendingDelete);
    });

    test('a still-pending (no token) link round-trips', () {
      const link = ShareLink(tripId: '20', needsSync: true);

      final result = ShareLink.fromCacheJson(link.toCacheJson());

      expect(result.token, isNull);
      expect(result.needsSync, isTrue);
    });
  });

  group('copyWith', () {
    test('only overrides needsSync/pendingDelete, keeping everything else', () {
      const link = ShareLink(tripId: '20', token: 'abc123', shareBudget: true);

      final result = link.copyWith(pendingDelete: true);

      expect(result.pendingDelete, isTrue);
      expect(result.needsSync, isFalse);
      expect(result.token, 'abc123');
      expect(result.shareBudget, isTrue);
    });
  });
}
