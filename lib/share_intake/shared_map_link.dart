/// Which maps app a shared link came from.
enum MapLinkProvider { google, apple, amap }

/// A Google Maps, Apple Maps, or Amap link pulled out of text another app
/// shared into Trek (e.g. Google Maps' "Share" sends `"Sky Tower\nhttps://maps.app.goo.gl/…"`).
///
/// Whatever can be read from the text alone — a coordinate and a place name
/// — is parsed here, with no network, so an import can still be queued
/// with useful data while offline. The server's `POST /api/maps/resolve-url`
/// is still the primary resolver (it follows short links and reverse
/// geocodes an address); see `ShareImportRepository`.
class SharedMapLink {
  const SharedMapLink({
    required this.url,
    required this.provider,
    this.suggestedName,
    this.lat,
    this.lng,
  });

  /// The map link itself, exactly as shared.
  final String url;
  final MapLinkProvider provider;

  /// A place name from the shared text (the line before the link), the
  /// Google `/place/<name>/` path segment, or Apple's `q=` parameter.
  final String? suggestedName;

  /// Coordinates read from the link itself, if it carries any. Short links
  /// (`maps.app.goo.gl`, `surl.amap.com`) never do.
  final double? lat;
  final double? lng;

  bool get hasCoordinates => lat != null && lng != null;

  /// Returns the first supported map link in [text], or `null` if there is
  /// none.
  static SharedMapLink? parse(String text) {
    for (final match in _urlPattern.allMatches(text)) {
      final raw = _trimTrailingPunctuation(match.group(0)!);
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.host.isEmpty) continue;
      final provider = providerFor(uri);
      if (provider == null) continue;

      // Amap spells coordinates `lng,lat` in GCJ-02, which needs a datum
      // conversion the server owns — so Amap links are never parsed locally.
      final coords = provider == MapLinkProvider.amap
          ? null
          : _extractCoords(raw);
      return SharedMapLink(
        url: raw,
        provider: provider,
        suggestedName:
            _nameFromText(text, match.start) ?? _nameFromUrl(uri, provider),
        lat: coords?.$1,
        lng: coords?.$2,
      );
    }
    return null;
  }

  /// Host rules mirror Trek's server (`isGoogleMapsHost`, `GOOGLE_SHORT_HOSTS`,
  /// `AMAP_HOSTS` in `server/src/nest/maps/`): Google on any country domain,
  /// matched by shape so `google.evil.com` doesn't qualify. Apple Maps is
  /// `maps.apple.com` only — the server reads its `ll=` coordinate.
  /// A `goo.gl` or bare `google.*` link must also be under `/maps`, the
  /// same check as the web client's `isGoogleMapsUrl`.
  static MapLinkProvider? providerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'maps.app.goo.gl' || _googleMapsHost.hasMatch(host)) {
      return MapLinkProvider.google;
    }
    if ((host == 'goo.gl' || _googleHost.hasMatch(host)) &&
        uri.path.startsWith('/maps')) {
      return MapLinkProvider.google;
    }
    if (host == 'maps.apple.com') return MapLinkProvider.apple;
    if (_amapHosts.contains(host)) return MapLinkProvider.amap;
    return null;
  }

  static final _urlPattern = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  );
  static final _googleMapsHost = RegExp(
    r'^maps\.google\.[a-z]{2,3}(\.[a-z]{2})?$',
  );
  static final _googleHost = RegExp(
    r'^(www\.)?google\.[a-z]{2,3}(\.[a-z]{2})?$',
  );
  static const _amapHosts = {
    'amap.com',
    'www.amap.com',
    'uri.amap.com',
    'wb.amap.com',
    'surl.amap.com',
    'gaode.com',
    'www.gaode.com',
  };

  static String _trimTrailingPunctuation(String url) =>
      url.replaceFirst(RegExp(r'[).,;!?]+$'), '');

  /// The same three encodings the server's `extractCoords` reads:
  /// `/@lat,lng,zoom`, the `!3dlat!4dlng` data param, and `?q=`/`?ll=`.
  static (double, double)? _extractCoords(String url) {
    final patterns = [
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
      RegExp(r'[?&](?:q|ll)=(-?\d+\.\d+),(-?\d+\.\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match == null) continue;
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat == null || lng == null) continue;
      if (lat.abs() > 90 || lng.abs() > 180) continue;
      return (lat, lng);
    }
    return null;
  }

  /// The first non-empty line of text before the link — Google and Apple
  /// Maps both share the place name first (then the address, then the
  /// link).
  static String? _nameFromText(String text, int linkStart) {
    final before = text.substring(0, linkStart).trim();
    if (before.isEmpty) return null;
    final line = before
        .split('\n')
        .first
        .trim()
        .replaceFirst(RegExp(r'[\s:(\-–—]+$'), '');
    if (line.isEmpty || _urlPattern.hasMatch(line)) return null;
    return line;
  }

  static String? _nameFromUrl(Uri uri, MapLinkProvider provider) {
    switch (provider) {
      case MapLinkProvider.google:
        final match = RegExp(r'/place/([^/@]+)').firstMatch(uri.path);
        if (match == null) return null;
        final name = Uri.decodeComponent(
          match.group(1)!.replaceAll('+', ' '),
        ).trim();
        return name.isEmpty ? null : name;
      case MapLinkProvider.apple:
        final q = uri.queryParameters['q']?.trim();
        // A `q=` that's itself a coordinate is a dropped pin, not a name.
        if (q == null || q.isEmpty || _extractCoords('?q=$q') != null) {
          return null;
        }
        return q;
      case MapLinkProvider.amap:
        return null;
    }
  }
}
