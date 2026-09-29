import 'package:flutter_test/flutter_test.dart';
import 'package:trek/deep_links/deep_link.dart';

void main() {
  DeepLink? parse(String s) => DeepLink.parse(Uri.parse(s));

  group('DeepLink.parse', () {
    test('parses a trek:// invite link with the segment as the host', () {
      expect(
        parse('trek://join/abc_DEF-123'),
        const JoinTripLink('abc_DEF-123'),
      );
    });

    test('parses a trek:/// invite link with an empty host', () {
      expect(parse('trek:///join/abc'), const JoinTripLink('abc'));
    });

    test('parses a Trek web invite URL and keeps its host', () {
      expect(
        parse('https://Trek.Example.com/join/abc'),
        const JoinTripLink('abc', sourceHost: 'trek.example.com'),
      );
    });

    test('parses a bare in-app path', () {
      expect(parse('/join/abc'), const JoinTripLink('abc'));
      expect(parse('/trips/42'), const OpenTripLink(42));
    });

    test('parses trip links under every form', () {
      expect(parse('trek://trips/7'), const OpenTripLink(7));
      expect(
        parse('http://192.168.1.50:3000/trips/7/'),
        const OpenTripLink(7, sourceHost: '192.168.1.50'),
      );
    });

    test('rejects non-numeric or non-positive trip ids', () {
      expect(parse('/trips/abc'), isNull);
      expect(parse('/trips/0'), isNull);
    });

    test('rejects unknown paths, extra segments, and other schemes', () {
      expect(parse('/shared/abc'), isNull);
      expect(parse('/join'), isNull);
      expect(parse('/join/abc/extra'), isNull);
      expect(parse('mailto:someone@example.com'), isNull);
      expect(parse('ftp://trek.example.com/join/abc'), isNull);
    });

    test('location round-trips back through parse', () {
      const link = JoinTripLink('a b');
      expect(link.location, '/join/a%20b');
      expect(parse(link.location), link);
    });
  });

  group('DeepLink.tryParseText', () {
    test('trims pasted whitespace', () {
      expect(
        DeepLink.tryParseText('  https://trek.example.com/join/abc\n'),
        const JoinTripLink('abc', sourceHost: 'trek.example.com'),
      );
    });

    test('returns null for garbage', () {
      expect(DeepLink.tryParseText('not a link'), isNull);
      expect(DeepLink.tryParseText('http://[::1'), isNull);
    });
  });
}
