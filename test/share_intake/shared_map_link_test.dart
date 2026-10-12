import 'package:flutter_test/flutter_test.dart';
import 'package:trek/share_intake/shared_map_link.dart';

void main() {
  group('SharedMapLink.parse', () {
    test('Google Maps share text: name line + short link', () {
      final link = SharedMapLink.parse(
        'Sky Tower\nVictoria St W, Auckland\nhttps://maps.app.goo.gl/AbC123',
      )!;

      expect(link.provider, MapLinkProvider.google);
      expect(link.url, 'https://maps.app.goo.gl/AbC123');
      expect(link.suggestedName, 'Sky Tower');
      expect(link.hasCoordinates, isFalse);
    });

    test('long Google link: coordinates and /place/ name', () {
      final link = SharedMapLink.parse(
        'https://www.google.com/maps/place/Sky+Tower/@-36.8484597,174.7621955,17z/data=!3m1',
      )!;

      expect(link.provider, MapLinkProvider.google);
      expect(link.suggestedName, 'Sky Tower');
      expect(link.lat, closeTo(-36.8484597, 1e-9));
      expect(link.lng, closeTo(174.7621955, 1e-9));
    });

    test('Google data param !3d!4d and country domains', () {
      final link = SharedMapLink.parse(
        'https://maps.google.co.uk/maps?foo=1!3d51.5007!4d-0.1246',
      )!;

      expect(link.provider, MapLinkProvider.google);
      expect(link.lat, 51.5007);
      expect(link.lng, -0.1246);
    });

    test('Apple Maps: ll= coordinates and q= name', () {
      final link = SharedMapLink.parse(
        'https://maps.apple.com/?address=Auckland&ll=-36.848460,174.762190&q=Sky%20Tower',
      )!;

      expect(link.provider, MapLinkProvider.apple);
      expect(link.suggestedName, 'Sky Tower');
      expect(link.lat, -36.84846);
      expect(link.lng, 174.76219);
    });

    test('Apple Maps dropped pin: a coordinate q= is not a name', () {
      final link = SharedMapLink.parse(
        'https://maps.apple.com/?q=-36.84846,174.76219',
      )!;

      expect(link.suggestedName, isNull);
      expect(link.lat, -36.84846);
    });

    test('Amap is recognized but never parsed locally (GCJ-02)', () {
      final link = SharedMapLink.parse(
        'https://uri.amap.com/marker?position=121.4737,31.2304&name=X',
      )!;

      expect(link.provider, MapLinkProvider.amap);
      expect(link.hasCoordinates, isFalse);
    });

    test('trailing punctuation is trimmed off the link', () {
      final link = SharedMapLink.parse(
        'Meet here (https://maps.app.goo.gl/xyz).',
      )!;

      expect(link.url, 'https://maps.app.goo.gl/xyz');
      expect(link.suggestedName, 'Meet here');
    });

    test('skips non-map links and returns the first map link', () {
      final link = SharedMapLink.parse(
        'See https://example.com and https://maps.app.goo.gl/one',
      )!;

      expect(link.url, 'https://maps.app.goo.gl/one');
    });

    test('rejects text with no supported map link', () {
      expect(SharedMapLink.parse('just some text'), isNull);
      expect(SharedMapLink.parse('https://example.com/maps/@1.0,2.0'), isNull);
      expect(SharedMapLink.parse('https://google.evil.com/maps/x'), isNull);
      expect(SharedMapLink.parse('https://www.google.com/search?q=x'), isNull);
      expect(SharedMapLink.parse('https://goo.gl/abc'), isNull);
    });

    test('ignores out-of-range coordinates', () {
      final link = SharedMapLink.parse(
        'https://www.google.com/maps/@123.0,200.0,10z',
      )!;

      expect(link.hasCoordinates, isFalse);
    });
  });
}
