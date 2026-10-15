import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/days/day_note_outbox.dart';

void main() {
  group('PreferencesDayNoteOutbox', () {
    late PreferencesDayNoteOutbox outbox;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      outbox = PreferencesDayNoteOutbox();
    });

    test('is empty before anything is queued', () async {
      expect(await outbox.read('20'), isEmpty);
    });

    test('persists each trip\'s queue independently', () async {
      await outbox.write('20', const [
        DayNoteOp(
          kind: DayNoteOpKind.update,
          dayId: 1,
          noteId: 7,
          fields: {'color': null},
        ),
      ]);

      final restored = await PreferencesDayNoteOutbox().read('20');
      expect(restored.single.noteId, 7);
      expect(restored.single.fields, {'color': null});
      expect(await outbox.read('21'), isEmpty);
    });

    test('writing an empty queue clears it', () async {
      await outbox.write('20', const [
        DayNoteOp(kind: DayNoteOpKind.delete, dayId: 1, noteId: 7),
      ]);
      await outbox.write('20', const []);

      expect(await outbox.read('20'), isEmpty);
    });
  });
}
