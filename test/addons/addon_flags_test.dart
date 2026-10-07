import 'package:flutter_test/flutter_test.dart';
import 'package:trek/addons/addon_flags.dart';

import 'addon_fixtures.dart';

void main() {
  group('AddonFlags.fromJson', () {
    test('parses the GET /api/addons body', () {
      final flags = AddonFlags.fromJson(addonsResponse());

      expect(flags.addons.map((a) => a.id), [
        'packing',
        'budget',
        'collab',
        'atlas',
        'journey',
        'immich',
      ]);
      expect(flags.addons.last.type, ServerAddon.photoProviderType);
      expect(flags.bagTracking, isTrue);
      expect(flags.collabFeatures.chat, isTrue);
      expect(flags.collabFeatures.polls, isFalse);
    });

    test('an add-on absent from the list is disabled', () {
      final flags = AddonFlags.fromJson(addonsResponse(budget: false));

      expect(flags.isEnabled(AddonIds.budget), isFalse);
      expect(flags.isEnabled(AddonIds.packing), isTrue);
      expect(flags.isEnabled(AddonIds.vacay), isFalse);
    });

    test('memories is on exactly when a photo provider is listed', () {
      expect(
        AddonFlags.fromJson(addonsResponse()).isEnabled(AddonIds.memories),
        isTrue,
      );
      expect(
        AddonFlags.fromJson(
          addonsResponse(journey: false),
        ).isEnabled(AddonIds.memories),
        isFalse,
      );
    });

    test('missing collab keys default to on and bag tracking to off', () {
      final flags = AddonFlags.fromJson({'addons': []});

      expect(flags.addons, isEmpty);
      expect(flags.collabFeatures.chat, isTrue);
      expect(flags.collabFeatures.whatsnext, isTrue);
      expect(flags.bagTracking, isFalse);
    });

    test('skips malformed add-on entries', () {
      final flags = AddonFlags.fromJson({
        'addons': [
          'nope',
          {'name': 'no id'},
          {'id': 'atlas', 'name': 'Atlas', 'type': 'global', 'enabled': true},
        ],
      });

      expect(flags.addons.map((a) => a.id), ['atlas']);
    });

    test('an entry with enabled false is not enabled', () {
      final flags = AddonFlags.fromJson({
        'addons': [
          {'id': 'atlas', 'name': 'Atlas', 'type': 'global', 'enabled': false},
        ],
      });

      expect(flags.isEnabled(AddonIds.atlas), isFalse);
    });
  });

  test('freshInstallDefaults match the server seed', () {
    const flags = AddonFlags.freshInstallDefaults;

    for (final id in [
      AddonIds.packing,
      AddonIds.budget,
      AddonIds.documents,
      AddonIds.collab,
      AddonIds.vacay,
      AddonIds.atlas,
      AddonIds.naverListImport,
    ]) {
      expect(flags.isEnabled(id), isTrue, reason: id);
    }
    for (final id in [
      AddonIds.journey,
      AddonIds.roadtrip,
      AddonIds.collections,
      AddonIds.mcp,
      AddonIds.airtrail,
      AddonIds.dawarich,
      AddonIds.llmParsing,
      AddonIds.memories,
    ]) {
      expect(flags.isEnabled(id), isFalse, reason: id);
    }
    expect(flags.bagTracking, isFalse);
  });

  test('CachedAddonFlags round-trips through JSON', () {
    final cached = CachedAddonFlags(
      flags: AddonFlags.fromJson(addonsResponse()),
      fetchedAt: DateTime.utc(2026, 10, 7, 9),
    );

    final restored = CachedAddonFlags.fromJson(cached.toJson());

    expect(restored.fetchedAt, cached.fetchedAt);
    expect(restored.flags.toJson(), cached.flags.toJson());
    expect(restored.flags.isEnabled(AddonIds.memories), isTrue);
  });
}
