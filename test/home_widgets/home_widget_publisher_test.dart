import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/home_widgets/home_widget_publisher.dart';
import 'package:trek/home_widgets/widget_trip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'getWidgetData' ? null : true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const trip = WidgetTrip(
    id: 20,
    title: 'New Zealand',
    startDate: '2026-11-02',
    endDate: '2026-11-20',
  );

  test(
    'writes the candidates as JSON and redraws the Android widget',
    () async {
      await PluginHomeWidgetPublisher(
        isSupported: true,
      ).publishNextTrip([trip]);

      final save = calls.firstWhere((c) => c.method == 'saveWidgetData');
      expect(save.arguments['id'], 'next_trip.candidates');
      expect(jsonDecode(save.arguments['data'] as String), [
        {
          'id': 20,
          'title': 'New Zealand',
          'start_date': '2026-11-02',
          'end_date': '2026-11-20',
        },
      ]);
      expect(calls.last.method, 'updateWidget');
      expect(
        calls.last.arguments['qualifiedAndroidName'],
        'com.trek.trek.NextTripWidgetProvider',
      );
    },
  );

  test('clear removes the data and redraws', () async {
    await PluginHomeWidgetPublisher(isSupported: true).clear();

    final save = calls.firstWhere((c) => c.method == 'saveWidgetData');
    expect(save.arguments['id'], 'next_trip.candidates');
    expect(save.arguments['data'], isNull);
    expect(calls.last.method, 'updateWidget');
  });

  test('does nothing on a platform without a widget', () async {
    final publisher = PluginHomeWidgetPublisher(isSupported: false);
    await publisher.publishNextTrip([trip]);
    await publisher.clear();

    expect(calls, isEmpty);
  });
}
