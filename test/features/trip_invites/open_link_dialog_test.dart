import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/deep_links/deep_link.dart';
import 'package:trek/features/trip_invites/open_link_dialog.dart';

void main() {
  const config = ServerConfig(
    publicUrl: 'https://trek.example.com',
    privateUrl: 'http://192.168.1.50:3000',
  );

  group('validateLinkText', () {
    test('accepts an invite link on the public server', () {
      final result = validateLinkText(
        'https://trek.example.com/join/tok',
        config,
      );
      expect(result.link, isA<JoinTripLink>());
      expect(result.error, isNull);
    });

    test('accepts a link on the private (LAN) server', () {
      final result = validateLinkText(
        'http://192.168.1.50:3000/trips/4',
        config,
      );
      expect(result.link, const OpenTripLink(4, sourceHost: '192.168.1.50'));
    });

    test('accepts a trek:// link, which carries no server', () {
      expect(validateLinkText('trek://join/tok', config).link, isNotNull);
    });

    test('rejects a link for a different server', () {
      final result = validateLinkText('https://other.example/join/tok', config);
      expect(result.link, isNull);
      expect(result.error, contains('other.example'));
    });

    test('rejects text that is not a Trek link', () {
      final result = validateLinkText('hello', config);
      expect(result.link, isNull);
      expect(result.error, 'Paste a Trek trip or invite link.');
    });
  });

  testWidgets('returns the parsed link, or shows the error inline', (
    tester,
  ) async {
    DeepLink? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                returned = await showOpenLinkDialog(context, config: config),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Paste a Trek trip or invite link.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://trek.example.com/join/tok',
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(returned, const JoinTripLink('tok', sourceHost: 'trek.example.com'));
  });
}
