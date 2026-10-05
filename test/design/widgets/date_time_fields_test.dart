import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/widgets/date_time_fields.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  group('DateField', () {
    testWidgets('shows the label and the formatted date with its year', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Start date',
            value: DateTime(2026, 3, 7),
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('Sat, Mar 7, 2026'), findsOneWidget);
    });

    testWidgets('opens a picker on the current value and reports the pick', (
      tester,
    ) async {
      DateTime? picked;
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Start date',
            value: DateTime(2026, 3, 7),
            onChanged: (value) => picked = value,
          ),
        ),
      );

      await tester.tap(find.byType(DateField));
      await tester.pumpAndSettle();
      expect(find.text('March 2026'), findsOneWidget);

      await tester.tap(find.text('12'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 3, 12));
    });

    testWidgets('opens on initialPickerDate while empty', (tester) async {
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'End date',
            value: null,
            initialPickerDate: DateTime(2027, 8, 1),
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(DateField));
      await tester.pumpAndSettle();
      expect(find.text('August 2027'), findsOneWidget);
    });

    testWidgets('clamps the initial picker date into the allowed range', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Day',
            value: DateTime(2020, 1, 1),
            firstDate: DateTime(2026, 5, 1),
            lastDate: DateTime(2026, 5, 31),
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(DateField));
      await tester.pumpAndSettle();
      expect(find.text('May 2026'), findsOneWidget);
    });

    testWidgets('dismissing the picker reports nothing', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _host(DateField(label: 'Day', value: null, onChanged: (_) => calls++)),
      );

      await tester.tap(find.byType(DateField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });

    testWidgets('clear button reports null and only shows when clearable '
        'and set', (tester) async {
      DateTime? reported = DateTime(2000);
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Day',
            value: DateTime(2026, 3, 7),
            clearable: true,
            onChanged: (value) => reported = value,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Clear Day'));
      expect(reported, isNull);

      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Day',
            value: null,
            clearable: true,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byTooltip('Clear Day'), findsNothing);

      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Day',
            value: DateTime(2026, 3, 7),
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byTooltip('Clear Day'), findsNothing);
    });

    testWidgets('does not open when disabled', (tester) async {
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'Day',
            value: null,
            enabled: false,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(DateField));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('shows errorText', (tester) async {
      await tester.pumpWidget(
        _host(
          DateField(
            label: 'End date',
            value: null,
            errorText: 'End must be after start',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('End must be after start'), findsOneWidget);
    });
  });

  group('TimeField', () {
    testWidgets('formats per the device 12/24-hour preference', (tester) async {
      const field = TimeField(
        label: 'Starts',
        value: TimeOfDay(hour: 14, minute: 5),
        onChanged: _ignore,
      );
      await tester.pumpWidget(_host(field));
      expect(find.text('2:05 PM'), findsOneWidget);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(alwaysUse24HourFormat: true),
          child: _host(field),
        ),
      );
      expect(find.text('14:05'), findsOneWidget);
    });

    testWidgets('reports the picked time', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(
        _host(
          TimeField(
            label: 'Starts',
            value: const TimeOfDay(hour: 9, minute: 0),
            onChanged: (value) => picked = value,
          ),
        ),
      );

      await tester.tap(find.byType(TimeField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(picked, const TimeOfDay(hour: 9, minute: 0));
    });

    testWidgets('clear button reports null', (tester) async {
      TimeOfDay? reported = const TimeOfDay(hour: 1, minute: 0);
      await tester.pumpWidget(
        _host(
          TimeField(
            label: 'Starts',
            value: const TimeOfDay(hour: 9, minute: 0),
            clearable: true,
            onChanged: (value) => reported = value,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Clear Starts'));
      expect(reported, isNull);
    });
  });
}

void _ignore(TimeOfDay? _) {}
