/// A link into the app, parsed from a URI the OS handed over (a `trek://`
/// custom-scheme link) or one the user pasted (a Trek web URL).
///
/// Trek is self-hosted, so web URLs are accepted from any host here — the
/// caller decides whether that host is the configured server (see
/// [DeepLink.parse]'s `sourceHost`).
sealed class DeepLink {
  const DeepLink({this.sourceHost});

  /// The host of the web URL this link was parsed from, or `null` for a
  /// `trek://` link or a bare in-app path, which carry no server identity.
  final String? sourceHost;

  /// The in-app route this link opens (a go_router location).
  String get location;

  static const scheme = 'trek';

  /// Parses [uri] into a [DeepLink], or returns `null` if it isn't one the
  /// app handles. Accepted shapes, mirroring Trek's web client routes:
  ///
  /// - `/join/<token>` — a trip invite link.
  /// - `/trips/<id>` — a trip (numeric id).
  ///
  /// each either as a bare path, under `trek://` (where the first segment
  /// may be the URI host, e.g. `trek://join/<token>`), or as an absolute
  /// `http(s)` URL on any host.
  static DeepLink? parse(Uri uri) {
    final List<String> segments;
    String? sourceHost;
    if (uri.scheme == scheme) {
      segments = [
        if (uri.host.isNotEmpty) uri.host,
        ...uri.pathSegments,
      ].where((s) => s.isNotEmpty).toList();
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (uri.host.isEmpty) return null;
      segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      sourceHost = uri.host.toLowerCase();
    } else if (uri.scheme.isEmpty && uri.host.isEmpty) {
      segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    } else {
      return null;
    }

    if (segments.length != 2) return null;
    final [head, value] = segments;
    switch (head) {
      case 'join':
        return JoinTripLink(value, sourceHost: sourceHost);
      case 'trips':
        final id = int.tryParse(value);
        if (id == null || id <= 0) return null;
        return OpenTripLink(id, sourceHost: sourceHost);
    }
    return null;
  }

  /// Parses user-entered text (e.g. pasted from a chat message), trimming
  /// whitespace first. Returns `null` for anything [parse] rejects.
  static DeepLink? tryParseText(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri == null ? null : parse(uri);
  }
}

/// A trip invite link (`/join/<token>` in Trek's web client) — opening it
/// lets a signed-in user join the trip as a member.
class JoinTripLink extends DeepLink {
  const JoinTripLink(this.token, {super.sourceHost});

  final String token;

  @override
  String get location => '/join/${Uri.encodeComponent(token)}';

  @override
  bool operator ==(Object other) =>
      other is JoinTripLink &&
      other.token == token &&
      other.sourceHost == sourceHost;

  @override
  int get hashCode => Object.hash(JoinTripLink, token, sourceHost);
}

/// A link to one trip (`/trips/<id>` in Trek's web client).
class OpenTripLink extends DeepLink {
  const OpenTripLink(this.tripId, {super.sourceHost});

  final int tripId;

  @override
  String get location => '/trips/$tripId';

  @override
  bool operator ==(Object other) =>
      other is OpenTripLink &&
      other.tripId == tripId &&
      other.sourceHost == sourceHost;

  @override
  int get hashCode => Object.hash(OpenTripLink, tripId, sourceHost);
}
