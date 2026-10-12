import 'dart:async';

import '../../network/api_exception.dart';
import '../../share_intake/shared_map_link.dart';
import 'share_import_api.dart';
import 'share_import_store.dart';

/// Name given to a place when neither the user, the server's resolver, nor
/// the shared text produced one — Trek requires a non-empty name.
const fallbackPlaceName = 'Shared place';

/// Result of [ShareImportRepository.importLink].
sealed class ShareImportOutcome {
  const ShareImportOutcome();
}

/// The place now exists in the trip's place pool.
class PlaceAdded extends ShareImportOutcome {
  const PlaceAdded({required this.placeId, required this.name});
  final int placeId;
  final String name;
}

/// The server couldn't be reached; the import is saved and will be sent by
/// a later [ShareImportRepository.flushPending].
class ImportQueued extends ShareImportOutcome {
  const ImportQueued();
}

/// The server refused the import (trip gone, no permission, invalid data).
/// It is not retried.
class ImportFailed extends ShareImportOutcome {
  const ImportFailed(this.message);
  final String message;
}

/// What a [ShareImportRepository.flushPending] call did.
class FlushReport {
  const FlushReport({
    this.added = const [],
    this.rejected = const [],
    this.remaining = 0,
  });

  /// Names of places that were created.
  final List<String> added;

  /// One message per import the server refused (and that was dropped).
  final List<String> rejected;

  /// Imports still queued for the current server.
  final int remaining;
}

enum _SendStatus { sent, offline, retryLater, rejected }

class _SendResult {
  const _SendResult(this.status, {this.placeId, this.name, this.message});
  final _SendStatus status;
  final int? placeId;
  final String? name;
  final String? message;
}

/// Adds map links shared from other apps to a trip's place pool,
/// offline-first:
///
/// - The trip picker reads the last-fetched trip list from
///   [ShareImportStore] first ([cachedTrips]) and refreshes it separately
///   ([refreshTrips]), so it never blocks on the network.
/// - An import is written to the local queue *before* it's sent, and only
///   removed once the server has accepted or refused it. A network failure
///   leaves it queued for [flushPending].
/// - Every queued import is tied to the server it was made against
///   ([currentServer]); a flush only sends the current server's entries.
///
/// The server's `POST /api/maps/resolve-url` is tried first for every
/// link (it follows short links and adds an address). If it can't resolve
/// one, the coordinates parsed locally by [SharedMapLink] are used; if there
/// are none, the place is created without a location and the link is kept
/// in its notes.
class ShareImportRepository {
  ShareImportRepository({
    required ShareImportApi api,
    required ShareImportStore store,
    required Future<String?> Function() currentServer,
    String Function()? newId,
  }) : _api = api,
       _store = store,
       _currentServer = currentServer,
       _newId = newId ?? _timestampId;

  final ShareImportApi _api;
  final ShareImportStore _store;
  final Future<String?> Function() _currentServer;
  final String Function() _newId;

  Future<void>? _lock;

  static int _idCounter = 0;
  static String _timestampId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  /// Serializes everything that reads-then-writes the queue, so a
  /// background flush and a tap on "Add" can't send the same import twice.
  Future<T> _locked<T>(Future<T> Function() body) async {
    while (_lock != null) {
      await _lock;
    }
    final completer = Completer<void>();
    _lock = completer.future;
    try {
      return await body();
    } finally {
      _lock = null;
      completer.complete();
    }
  }

  /// The trip list last fetched from the current server, or `null` if it
  /// has never been fetched.
  Future<List<ShareTargetTrip>?> cachedTrips() async {
    final server = await _currentServer();
    if (server == null) return null;
    return _store.readTrips(server);
  }

  /// Fetches the trip list and caches it. Throws [ApiException] (including
  /// [NetworkException] when offline) — the cached list is left as it was.
  Future<List<ShareTargetTrip>> refreshTrips() async {
    final server = await _currentServer();
    final trips = await _api.listTrips();
    if (server != null) await _store.writeTrips(server, trips);
    return trips;
  }

  /// Number of imports still queued for the current server.
  Future<int> pendingCount() async {
    final server = await _currentServer();
    final pending = await _store.readPending();
    return pending.where((item) => item.serverUrl == server).length;
  }

  /// Adds [link] to [trip]'s place pool, named [name] if the user gave one.
  Future<ShareImportOutcome> importLink({
    required ShareTargetTrip trip,
    required SharedMapLink link,
    String? name,
  }) async {
    final server = await _currentServer();
    if (server == null) {
      return const ImportFailed('No Trek server is configured.');
    }
    final trimmedName = name?.trim();
    final item = PendingPlaceImport(
      id: _newId(),
      serverUrl: server,
      tripId: trip.id,
      tripTitle: trip.title,
      url: link.url,
      provider: link.provider,
      name: (trimmedName == null || trimmedName.isEmpty) ? null : trimmedName,
      suggestedName: link.suggestedName,
      lat: link.lat,
      lng: link.lng,
    );

    return _locked(() async {
      await _store.writePending([...await _store.readPending(), item]);
      final result = await _send(item);
      switch (result.status) {
        case _SendStatus.sent:
          await _remove(item.id);
          return PlaceAdded(placeId: result.placeId!, name: result.name!);
        case _SendStatus.rejected:
          await _remove(item.id);
          return ImportFailed(result.message!);
        case _SendStatus.offline:
        case _SendStatus.retryLater:
          return const ImportQueued();
      }
    });
  }

  /// Sends the current server's queued imports in order. Stops at the
  /// first network failure (the rest would fail the same way); drops
  /// imports the server refuses; keeps ones that hit a transient server
  /// error for next time.
  Future<FlushReport> flushPending() async {
    final server = await _currentServer();
    if (server == null) return const FlushReport();

    return _locked(() async {
      final added = <String>[];
      final rejected = <String>[];
      final queue = (await _store.readPending())
          .where((item) => item.serverUrl == server)
          .toList();

      for (final item in queue) {
        final result = await _send(item);
        if (result.status == _SendStatus.offline) break;
        if (result.status == _SendStatus.retryLater) continue;
        await _remove(item.id);
        if (result.status == _SendStatus.sent) {
          added.add(result.name!);
        } else {
          rejected.add(
            'Couldn\'t add a shared place to "${item.tripTitle}": '
            '${result.message}',
          );
        }
      }

      final remaining = (await _store.readPending())
          .where((item) => item.serverUrl == server)
          .length;
      return FlushReport(
        added: added,
        rejected: rejected,
        remaining: remaining,
      );
    });
  }

  Future<void> _remove(String id) async {
    final pending = await _store.readPending();
    await _store.writePending(pending.where((item) => item.id != id).toList());
  }

  Future<_SendResult> _send(PendingPlaceImport item) async {
    ResolvedMapLink? resolved;
    try {
      resolved = await _api.resolveUrl(item.url);
    } on NetworkException {
      return const _SendResult(_SendStatus.offline);
    } on UnauthorizedException {
      return const _SendResult(_SendStatus.retryLater);
    } on ApiException {
      // Unresolvable (400), SSRF-blocked (403), or the resolver itself
      // failed — fall back to what was parsed locally.
      resolved = null;
    }

    final name =
        item.name ?? resolved?.name ?? item.suggestedName ?? fallbackPlaceName;
    final lat = resolved?.lat ?? item.lat;
    final lng = resolved?.lng ?? item.lng;
    final hasLocation = lat != null && lng != null;
    final body = <String, dynamic>{
      'name': name,
      if (hasLocation) 'lat': lat,
      if (hasLocation) 'lng': lng,
      if (resolved?.address != null) 'address': resolved!.address,
      if (resolved?.googleFtid != null) 'google_ftid': resolved!.googleFtid,
      if (!hasLocation) 'notes': item.url,
    };

    try {
      final placeId = await _api.createPlace(item.tripId, body);
      return _SendResult(_SendStatus.sent, placeId: placeId, name: name);
    } on NetworkException {
      return const _SendResult(_SendStatus.offline);
    } on UnauthorizedException {
      return const _SendResult(_SendStatus.retryLater);
    } on ForbiddenException catch (error) {
      return _SendResult(_SendStatus.rejected, message: error.message);
    } on ValidationException catch (error) {
      return _SendResult(_SendStatus.rejected, message: error.message);
    } on ServerException catch (error) {
      if (error.statusCode == 404) {
        return _SendResult(_SendStatus.rejected, message: error.message);
      }
      // 429 / 5xx — the server is up but not taking it right now.
      return const _SendResult(_SendStatus.retryLater);
    }
  }
}
