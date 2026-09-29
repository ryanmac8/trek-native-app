import 'dart:async';

import '../../network/api_exception.dart';
import 'pending_invite_store.dart';
import 'trip_invite_api.dart';

/// The state of an invite as shown before the user confirms joining.
sealed class InviteLookup {
  const InviteLookup();
}

/// The server resolved the token to a trip.
class InviteFound extends InviteLookup {
  const InviteFound({required this.tripId, required this.title});

  final int tripId;
  final String title;
}

/// The server couldn't be reached. [cached] is the locally remembered
/// invite (with the last-seen trip title, if any), or `null` if this
/// invite was never seen before.
class InviteOffline extends InviteLookup {
  const InviteOffline(this.cached);

  final PendingInvite? cached;
}

/// The server says the token is unknown, rotated, disabled, or expired.
class InviteInvalid extends InviteLookup {
  const InviteInvalid(this.message);

  final String message;
}

/// Any other server-side failure (rate limit, 5xx, …) — worth retrying.
class InviteLookupFailed extends InviteLookup {
  const InviteLookupFailed(this.message);

  final String message;
}

/// The result of confirming (or retrying) a join.
sealed class JoinOutcome {
  const JoinOutcome(this.token);

  final String token;
}

/// The server accepted the join. [joined] is `false` when the user already
/// had access to the trip.
class JoinCompleted extends JoinOutcome {
  const JoinCompleted(
    super.token, {
    required this.tripId,
    required this.joined,
    this.tripTitle,
  });

  final int tripId;
  final bool joined;
  final String? tripTitle;
}

/// Offline: the join is saved locally and will be sent by [flushQueued].
class JoinQueued extends JoinOutcome {
  const JoinQueued(super.token);
}

/// The invite is no longer valid; it has been dropped locally.
class JoinInvalid extends JoinOutcome {
  const JoinInvalid(super.token, this.message);

  final String message;
}

/// The server rejected the join for another reason; nothing is queued.
class JoinFailed extends JoinOutcome {
  const JoinFailed(super.token, this.message);

  final String message;
}

/// Opening and accepting trip invite links, offline-first: a join confirmed
/// while the server is unreachable is persisted in [PendingInviteStore] and
/// sent later by [flushQueued]; a link opened while signed out is
/// remembered so it can be resumed after login.
///
/// Every entry is scoped to the configured public server URL (via
/// [currentServer], a local read), so switching servers never sends one
/// server's token to another.
class TripInviteRepository {
  TripInviteRepository({
    required TripInviteApi api,
    required PendingInviteStore store,
    required Future<String?> Function() currentServer,
  }) : _api = api,
       _store = store,
       _currentServer = currentServer;

  final TripInviteApi _api;
  final PendingInviteStore _store;
  final Future<String?> Function() _currentServer;

  /// Serializes store read-modify-write cycles and accept calls, so a
  /// background [flushQueued] and a user-initiated [accept] can't both send
  /// (or both drop) the same invite.
  Future<void>? _lock;

  Future<T> _locked<T>(Future<T> Function() body) {
    final previous = _lock;
    final result = previous == null ? body() : previous.then((_) => body());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Remembers [token] as opened-but-unconfirmed for the current server,
  /// unless it's already remembered (keeping any queued state). No-op when
  /// no server is configured.
  Future<void> remember(String token) => _locked(() async {
    final server = await _currentServer();
    if (server != null) await _rememberUnlocked(server, token);
  });

  Future<void> _rememberUnlocked(String server, String token) async {
    if (await _find(server, token) != null) return;
    await _store.put(PendingInvite(token: token, server: server));
  }

  /// The oldest remembered invite for the current server that the user
  /// hasn't confirmed yet, if any.
  Future<PendingInvite?> firstUnconfirmed() async {
    final server = await _currentServer();
    if (server == null) return null;
    final all = await _store.readAll();
    for (final invite in all) {
      if (invite.server == server && !invite.acceptQueued) return invite;
    }
    return null;
  }

  /// Every invite the user confirmed that hasn't reached the server yet.
  Future<List<PendingInvite>> queued() async {
    final server = await _currentServer();
    if (server == null) return [];
    return (await _store.readAll())
        .where((e) => e.server == server && e.acceptQueued)
        .toList();
  }

  /// Resolves [token] on the server. Refreshes the cached trip title of a
  /// remembered invite on success and drops it on a 404.
  Future<InviteLookup> lookup(String token) async {
    final server = await _currentServer();
    try {
      final preview = await _api.preview(token);
      if (server != null) {
        await _locked(() async {
          final cached = await _find(server, token);
          if (cached != null) {
            await _store.put(
              cached.copyWith(tripId: preview.tripId, tripTitle: preview.title),
            );
          }
        });
      }
      return InviteFound(tripId: preview.tripId, title: preview.title);
    } on NetworkException {
      return InviteOffline(server == null ? null : await _find(server, token));
    } on ServerException catch (e) {
      if (e.statusCode == 404) {
        if (server != null) {
          await _locked(() => _store.remove(server: server, token: token));
        }
        return InviteInvalid(e.message);
      }
      return InviteLookupFailed(e.message);
    } on UnauthorizedException {
      // The session was cleared and the router is heading to login — keep
      // the invite so it's offered again afterwards.
      if (server != null) {
        await _locked(() => _rememberUnlocked(server, token));
      }
      rethrow;
    } on ApiException catch (e) {
      return InviteLookupFailed(e.message);
    }
  }

  /// Confirms joining via [token]. Offline, the join is queued locally and
  /// [JoinQueued] is returned rather than an error.
  /// Rethrows [UnauthorizedException] after remembering the invite, so it's
  /// offered again after the next login.
  Future<JoinOutcome> accept(String token) => _locked(() async {
    final server = await _currentServer();
    final cached = server == null ? null : await _find(server, token);
    return _send(server, token, cached, queueOnNetworkError: true);
  });

  /// Drops [token] locally (the user declined, or dismissed a queued join).
  Future<void> discard(String token) => _locked(() async {
    final server = await _currentServer();
    if (server == null) return;
    await _store.remove(server: server, token: token);
  });

  /// Sends every queued join for the current server, oldest first. Stops at
  /// the first network failure (the rest stay queued). Returns the outcome
  /// of each invite the server answered for: completed and invalid ones are
  /// dropped locally, [JoinFailed] ones stay queued for the next flush.
  Future<List<JoinOutcome>> flushQueued() => _locked(() async {
    final server = await _currentServer();
    if (server == null) return const [];
    final outcomes = <JoinOutcome>[];
    final pending = (await _store.readAll()).where(
      (e) => e.server == server && e.acceptQueued,
    );
    for (final invite in pending) {
      final outcome = await _send(
        server,
        invite.token,
        invite,
        queueOnNetworkError: false,
      );
      if (outcome is JoinQueued) break;
      outcomes.add(outcome);
    }
    return outcomes;
  });

  Future<JoinOutcome> _send(
    String? server,
    String token,
    PendingInvite? cached, {
    required bool queueOnNetworkError,
  }) async {
    try {
      final result = await _api.accept(token);
      if (server != null) await _store.remove(server: server, token: token);
      return JoinCompleted(
        token,
        tripId: result.tripId,
        joined: result.joined,
        tripTitle: cached?.tripTitle,
      );
    } on NetworkException {
      if (queueOnNetworkError && server != null) {
        await _store.put(
          (cached ?? PendingInvite(token: token, server: server)).copyWith(
            acceptQueued: true,
          ),
        );
      }
      return JoinQueued(token);
    } on ServerException catch (e) {
      if (e.statusCode == 404) {
        if (server != null) await _store.remove(server: server, token: token);
        return JoinInvalid(token, e.message);
      }
      return JoinFailed(token, e.message);
    } on UnauthorizedException {
      if (server != null) await _rememberUnlocked(server, token);
      rethrow;
    } on ApiException catch (e) {
      return JoinFailed(token, e.message);
    }
  }

  Future<PendingInvite?> _find(String server, String token) async {
    for (final invite in await _store.readAll()) {
      if (invite.server == server && invite.token == token) return invite;
    }
    return null;
  }
}
