import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/formats/trek_date_range.dart';
import 'package:trek/design/widgets/date_range_field.dart';
import 'package:trek/design/widgets/date_time_fields.dart';

/// Hosts a [DateRangeField] that owns its value, the way a form would.
class _Host extends StatefulWidget {
  const _Host({required this.initial, this.maxDays = 999, this.onChanged});

  final TrekDateRange initial;
  final int? maxDays;
  final ValueChanged<TrekDateRange>? onChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late TrekDateRange _value = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DateRangeField(
          value: _value,
          maxDays: widget.maxDays,
          onChanged: (range) {
            widget.onChanged?.call(range);
            setState(() => _value = range);
          },
        ),
      ),
    ),
  );
}

Finder _field(String label) =>
    find.byWidgetPredicate((w) => w is DateField && w.label == label);

void main() {
  testWidgets('picking a start shifts the end to keep the trip length', (
    tester,
  ) async {
    TrekDateRange? reported;
    await tester.pumpWidget(
      _Host(
        initial: TrekDateRange(
          start: DateTime(2026, 3, 2),
          end: DateTime(2026, 3, 5),
        ),
        onChanged: (range) => reported = range,
      ),
    );
    expect(find.text('Mon, Mar 2, 2026'), findsOneWidget);
    expect(find.text('Thu, Mar 5, 2026'), findsOneWidget);

    await tester.tap(_field('Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      reported,
      TrekDateRange(start: DateTime(2026, 3, 4), end: DateTime(2026, 3, 7)),
    );
    expect(find.text('Wed, Mar 4, 2026'), findsOneWidget);
    expect(find.text('Sat, Mar 7, 2026'), findsOneWidget);
  });

  testWidgets('the end picker opens on the start and blocks earlier days', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(initial: TrekDateRange(start: DateTime(2026, 3, 10))),
    );

    await tester.tap(_field('End date'));
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);

    // Days before the start are disabled; tapping one changes nothing.
    await tester.tap(find.text('9'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Tue, Mar 10, 2026'), findsNWidgets(2));
  });

  testWidgets('limits the end picker to maxDays from the start', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(initial: TrekDateRange(start: DateTime(2026, 3, 10)), maxDays: 3),
    );

    await tester.tap(_field('End date'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, DateTime(2026, 3, 10));
    expect(picker.lastDate, DateTime(2026, 3, 12));
  });

  testWidgets('shows the validation message for an inverted range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(
        initial: TrekDateRange(
          start: DateTime(2026, 3, 10),
          end: DateTime(2026, 3, 8),
        ),
      ),
    );
    expect(find.text('End date must be after start date'), findsOneWidget);
  });

  testWidgets('clearing the end keeps the start', (tester) async {
    TrekDateRange? reported;
    await tester.pumpWidget(
      _Host(
        initial: TrekDateRange(
          start: DateTime(2026, 3, 10),
          end: DateTime(2026, 3, 12),
        ),
        onChanged: (range) => reported = range,
      ),
    );

    await tester.tap(find.byTooltip('Clear End date'));
    await tester.pump();
    expect(reported, TrekDateRange(start: DateTime(2026, 3, 10)));
  });
}
